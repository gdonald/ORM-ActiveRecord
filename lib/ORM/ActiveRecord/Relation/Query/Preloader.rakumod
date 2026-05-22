
use ORM::ActiveRecord::Support::Utils;

role QueryPreloader is export {
  method apply-preloads(@records) {
    return @records unless @records.elems;
    my @specs = (|self.preloads-values, |self.eager-loads-values);
    return @records unless @specs.elems;
    self!preload-specs(@records, @specs);
    @records;
  }

  method !preload-specs(@records, @specs) {
    return unless @records.elems;
    for @specs -> $spec {
      given $spec {
        when Pair {
          my $name = $spec.key.Str;
          self!preload-one-grouped(@records, $name);
          my @children = self!collect-children(@records, $name);
          self!preload-nested(@children, $spec.value);
        }
        default {
          self!preload-one-grouped(@records, $spec.Str);
        }
      }
    }
  }

  method !preload-nested(@children, $nested) {
    return unless @children.elems;
    return if $nested === True;
    given $nested {
      when Bool     { return }
      when Pair     { self!preload-specs(@children, ($nested,)) }
      when Hash | Map {
        my @sub;
        for $nested.kv -> $k, $v { @sub.push: ($k.Str => $v) }
        self!preload-specs(@children, @sub);
      }
      when Iterable { self!preload-specs(@children, $nested.list) }
      default       { self!preload-specs(@children, ($nested.Str,)) }
    }
  }

  method !preload-one-grouped(@records, Str:D $name) {
    return unless @records.elems;
    my %by-class;
    my @order;
    for @records -> $r {
      my $cname = $r.WHAT.^name;
      unless %by-class{$cname}:exists {
        %by-class{$cname} = [];
        @order.push: $cname;
      }
      %by-class{$cname}.push: $r;
    }
    if @order.elems == 1 {
      self!preload-one(@records, $name);
      return;
    }
    for @order -> $cname {
      my @group = %by-class{$cname}.list;
      my $sample = @group[0];
      next unless self!sample-has-assoc($sample, $name);
      self!preload-one(@group, $name);
    }
  }

  method !sample-has-assoc($sample, Str:D $name --> Bool) {
    return True if $sample.belongs-tos{$name}:exists;
    return True if $sample.has-manys{$name}:exists;
    return True if $sample.has-ones{$name}:exists;
    return True if $sample.habtms{$name}:exists;
    False;
  }

  method !collect-children(@records, Str:D $name) {
    my @out;
    for @records -> $r {
      next unless $r.assoc-cache{$name}:exists;
      my $v = $r.assoc-cache{$name};
      next unless $v.defined;
      given $v {
        when Iterable { @out.append: $v.list.grep(*.defined) }
        default       { @out.push: $v if $v.defined }
      }
    }
    @out;
  }

  method !preload-one(@records, Str:D $name) {
    return unless @records.elems;
    my $sample = @records[0];
    if $sample.belongs-tos{$name}:exists {
      self!preload-belongs-to(@records, $name, $sample.belongs-tos{$name});
    }
    elsif $sample.has-manys{$name}:exists {
      self!preload-has-many(@records, $name, $sample.has-manys{$name});
    }
    elsif $sample.has-ones{$name}:exists {
      self!preload-has-one(@records, $name, $sample.has-ones{$name});
    }
    elsif $sample.habtms{$name}:exists {
      self!preload-habtm(@records, $name, $sample.habtms{$name});
    }
    else {
      die "preload: unknown association '$name' on " ~ $sample.WHAT.^name;
    }
  }

  method !preload-belongs-to(@records, Str:D $name, $spec) {
    my $sample = @records[0];
    if $sample.is-polymorphic-assoc($name) {
      my %by-type;
      for @records -> $r {
        my $t = $r.attrs{$name ~ '_type'};
        my $i = $r.attrs{$name ~ '_id'};
        next unless $t && $i;
        %by-type{$t}.push: $r;
      }
      for %by-type.kv -> $type-name, @parents {
        my $class = @parents[0].polymorphic-class-for($name, $type-name);
        next if $class === Nil || $class === Any || $class === Mu;
        next if $class.defined;
        my @ids = @parents.map({ .attrs{$name ~ '_id'} }).unique;
        my $q = $class.where(:id(@ids.list));
        my %by-id;
        for $q.all -> $c { %by-id{$c.id} = $c }
        for @parents -> $p {
          my $i = $p.attrs{$name ~ '_id'};
          $p.assoc-cache{$name} = %by-id{$i} // Nil;
        }
      }
      for @records -> $r {
        next if $r.assoc-cache{$name}:exists;
        $r.assoc-cache{$name} = Nil;
      }
      return;
    }
    my $class    = $sample.assoc-class-from-spec($spec);
    my $fkey-col = $sample.assoc-fkey-from-spec($spec, $name ~ '_id');
    my $pkey-col = $sample.assoc-pkey-from-spec($spec, 'id');
    my @fkey-vals = @records.map({ .attrs{$fkey-col} }).grep(*.defined).grep(* != 0).unique;
    my %by-pkey;
    if @fkey-vals.elems {
      my $q = $class.where(($pkey-col => @fkey-vals.list).Hash);
      for $q.all -> $c {
        my $k = $pkey-col eq 'id' ?? $c.id !! $c.attrs{$pkey-col};
        %by-pkey{$k} = $c;
      }
    }
    for @records -> $r {
      my $k = $r.attrs{$fkey-col};
      $r.assoc-cache{$name} = ($k.defined && $k != 0) ?? (%by-pkey{$k} // Nil) !! Nil;
    }
  }

  method !preload-has-many(@records, Str:D $name, $spec) {
    my $sample = @records[0];
    if $sample.assoc-spec-has($spec, 'through') {
      self!preload-through-many(@records, $name, $spec);
      return;
    }
    if $sample.assoc-spec-has($spec, 'as') {
      my $as-name = ~$sample.assoc-spec-value($spec, 'as');
      my $class = $sample.assoc-class-from-spec($spec);
      my $type-name = $sample.polymorphic-name;
      my @pkeys = @records.map(*.id).unique;
      my @children;
      if @pkeys.elems {
        my %where = ($as-name ~ '_id') => @pkeys.list, ($as-name ~ '_type') => $type-name;
        @children = $class.where(%where).all;
      }
      my %by-pkey;
      for @children -> $c { %by-pkey{$c.attrs{$as-name ~ '_id'}}.push: $c }
      for @records -> $r {
        $r.assoc-cache{$name} = (%by-pkey{$r.id} // []).list;
      }
      return;
    }
    my $class = $sample.assoc-class-from-spec($spec);
    if $class === Mu {
      self!preload-via-collection(@records, $name);
      return;
    }
    my $fkey-name = $sample.assoc-fkey-from-spec($spec, Utils.base-name($sample.fkey-name));
    my $pkey-col  = $sample.assoc-pkey-from-spec($spec, 'id');
    my @pkey-vals = @records.map({ $pkey-col eq 'id' ?? .id !! .attrs{$pkey-col} }).grep(*.defined).unique;
    my @children;
    if @pkey-vals.elems {
      @children = $class.where(($fkey-name => @pkey-vals.list).Hash).all;
    }
    my %by-pkey;
    for @children -> $c { %by-pkey{$c.attrs{$fkey-name}}.push: $c }
    for @records -> $r {
      my $k = $pkey-col eq 'id' ?? $r.id !! $r.attrs{$pkey-col};
      $r.assoc-cache{$name} = (%by-pkey{$k} // []).list;
    }
  }

  method !preload-has-one(@records, Str:D $name, $spec) {
    my $sample = @records[0];
    if $sample.assoc-spec-has($spec, 'through') {
      self!preload-through-one(@records, $name, $spec);
      return;
    }
    my $class = $sample.assoc-class-from-spec($spec);
    if $class === Mu {
      self!preload-via-direct(@records, $name);
      return;
    }
    my $fkey-name = Utils.base-name($sample.fkey-name);
    if $sample.assoc-spec-has($spec, 'foreign-key') {
      $fkey-name = ~$sample.assoc-spec-value($spec, 'foreign-key');
    }
    my $pkey-col = 'id';
    if $sample.assoc-spec-has($spec, 'primary-key') {
      $pkey-col = ~$sample.assoc-spec-value($spec, 'primary-key');
    }
    my @pkey-vals = @records.map({ $pkey-col eq 'id' ?? .id !! .attrs{$pkey-col} }).grep(*.defined).unique;
    my @children;
    if @pkey-vals.elems {
      @children = $class.where(($fkey-name => @pkey-vals.list).Hash).all;
    }
    my %by-pkey;
    for @children -> $c {
      my $k = $c.attrs{$fkey-name};
      %by-pkey{$k} //= $c;
    }
    for @records -> $r {
      my $k = $pkey-col eq 'id' ?? $r.id !! $r.attrs{$pkey-col};
      $r.assoc-cache{$name} = %by-pkey{$k} // Nil;
    }
  }

  method !preload-habtm(@records, Str:D $name, $spec) {
    self!preload-via-collection(@records, $name);
  }

  method !preload-via-collection(@records, Str:D $name) {
    for @records -> $r {
      my @loaded = $r."$name"().list;
      $r.assoc-cache{$name} = @loaded;
    }
  }

  method !preload-via-direct(@records, Str:D $name) {
    for @records -> $r {
      $r.assoc-cache{$name} = $r."$name"();
    }
  }

  method !preload-through-many(@records, Str:D $name, $spec) {
    my $sample = @records[0];
    my $through-pair = $sample.assoc-spec-value($spec, 'through');
    return self!preload-via-collection(@records, $name) unless $through-pair.defined;
    my $through-name = ~$through-pair.key;

    self!preload-one-grouped(@records, $through-name);

    my @joins;
    for @records -> $r {
      my $v = $r.assoc-cache{$through-name};
      next unless $v.defined;
      given $v {
        when Iterable { @joins.append: $v.list.grep(*.defined) }
        default       { @joins.push: $v }
      }
    }

    my $source = $sample.assoc-source-name($spec, Utils.singular($name));

    if @joins.elems {
      self!preload-one-grouped(@joins, $source);
    }

    for @records -> $r {
      my @targets;
      my $v = $r.assoc-cache{$through-name};
      if $v.defined {
        for $v.list -> $j {
          next unless $j.defined;
          next unless $j.assoc-cache{$source}:exists;
          my $tv = $j.assoc-cache{$source};
          next unless $tv.defined;
          given $tv {
            when Iterable { @targets.append: $tv.list.grep(*.defined) }
            default       { @targets.push: $tv }
          }
        }
      }
      $r.assoc-cache{$name} = @targets;
    }
  }

  method !preload-through-one(@records, Str:D $name, $spec) {
    my $sample = @records[0];
    my $through-pair = $sample.assoc-spec-value($spec, 'through');
    return self!preload-via-direct(@records, $name) unless $through-pair.defined;
    my $through-name = ~$through-pair.key;

    self!preload-one-grouped(@records, $through-name);

    my @joins;
    for @records -> $r {
      my $v = $r.assoc-cache{$through-name};
      next unless $v.defined;
      @joins.push: $v;
    }

    my $source = $sample.assoc-source-name($spec, $name);

    if @joins.elems {
      self!preload-one-grouped(@joins, $source);
    }

    for @records -> $r {
      my $j = $r.assoc-cache{$through-name};
      my $has-source = $j.defined ?? ($j.assoc-cache{$source}:exists) !! False;
      if $has-source {
        $r.assoc-cache{$name} = $j.assoc-cache{$source};
      } else {
        $r.assoc-cache{$name} = Nil;
      }
    }
  }
}
