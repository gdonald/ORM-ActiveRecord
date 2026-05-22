
use ORM::ActiveRecord::Support::Utils;

role QueryModifiers is export {
  method none {
    self.is-none-value = True;
    self;
  }

  method create-with(Hash:D $attrs) {
    for $attrs.kv -> $k, $v { self.create-with-attrs{$k} = $v }
    self;
  }

  method with(*%kw) {
    die 'with requires at least one CTE' unless %kw.elems;
    for %kw.kv -> $k, $v { self.ctes-values.push: %( name => $k.Str, sub => $v, recursive => False ) }
    self;
  }

  method with-recursive(*%kw) {
    die 'with-recursive requires at least one CTE' unless %kw.elems;
    for %kw.kv -> $k, $v { self.ctes-values.push: %( name => $k.Str, sub => $v, recursive => True ) }
    self;
  }

  method annotate(*@comments) {
    die 'annotate requires at least one comment' unless @comments.elems;
    self.annotations-values.append: @comments.map({ .Str });
    self;
  }

  method optimizer-hints(*@hints) {
    die 'optimizer-hints requires at least one hint' unless @hints.elems;
    self.optimizer-hints-values.append: @hints.map({ .Str });
    self;
  }

  method unscope(*@kinds, *%kw) {
    my @all-kinds = @kinds.map(*.Str);
    for %kw.kv -> $kind, $val {
      if $val === True {
        @all-kinds.push: $kind;
      } else {
        given $kind {
          when 'where' {
            my @cols = $val ~~ Iterable ?? $val.list.map(*.Str) !! ($val.Str,);
            for @cols -> $c {
              self.where-values{$c}:delete;
              self.where-not-values{$c}:delete;
            }
          }
          default { die "unscope: '$kind' does not accept a column argument" }
        }
      }
    }

    for @all-kinds.unique -> $kind {
      given $kind {
        when 'where'           { self.where-values = {}; self.where-not-values = {} }
        when 'order'           { self.order-values = () }
        when 'limit'           { self.limit-value = 0 }
        when 'offset'          { self.offset-value = 0 }
        when 'select'          { self.select-values = () }
        when 'distinct'        { self.distinct-value = False }
        when 'group'           { self.group-values = () }
        when 'having'          { self.having-values = () }
        when 'from'            { self.from-source = Str; self.from-alias = Str }
        when 'references'      { self.references-values = () }
        when 'readonly'        { self.readonly-value = False }
        when 'joins'           { self.joins-values = () }
        when 'with'            { self.ctes-values = () }
        when 'annotate'        { self.annotations-values = () }
        when 'optimizer-hints' { self.optimizer-hints-values = () }
        when 'lock'            { self.lock-value = False }
        default { die "unscope: unknown scope kind '$kind'" }
      }
    }
    self;
  }

  method order(*@cols, *%kw) {
    for @cols -> $c {
      given $c {
        when Pair { self.order-values.push: self!format-direction(.key, .value) }
        when Str  { self.order-values.push: $c }
        default   { self.order-values.push: $c.Str }
      }
    }
    for %kw.kv -> $k, $v { self.order-values.push: self!format-direction($k, $v) }
    self;
  }

  method reorder(*@cols, *%kw) {
    self.order-values = ();
    self.order(|@cols, |%kw);
  }

  method in-order-of($col, @values) {
    die 'in-order-of requires at least one value' unless @values.elems;
    my @parts = ('CASE',);
    for @values.kv -> $i, $v {
      @parts.push: "WHEN {$col.Str} = ? THEN $i";
    }
    @parts.push: "ELSE { @values.elems }";
    @parts.push: 'END';
    self.order-values.push: ((@parts.join(' '), |@values).List);
    self;
  }

  method !format-direction($col, $dir --> Str) {
    my $d;
    given $dir {
      when Bool { $d = 'ASC' }
      when Pair { $d = $dir.key.Str.uc }
      default   { $d = $dir.Str.uc }
    }
    die "order: invalid direction '$dir' for {$col.Str}"
    unless $d eq 'ASC' || $d eq 'DESC';
    "{$col.Str} $d";
  }

  method limit(Int:D $n) {
    self.limit-value = $n;
    self;
  }

  method offset(Int:D $n) {
    self.offset-value = $n;
    self;
  }

  method select(*@cols) {
    self.select-values.append: @cols.map({ .Str });
    self;
  }

  method distinct(Bool:D $on = True) {
    self.distinct-value = $on;
    self;
  }

  method group(*@cols) {
    self.group-values.append: @cols.map({ .Str });
    self;
  }

  method regroup(*@cols) {
    self.group-values = @cols.map({ .Str });
    self;
  }

  method from($source, Str $alias?) {
    self.from-source = $source.Str;
    self.from-alias = $alias.defined ?? $alias.Str !! Str;
    self;
  }

  method references(*@names, *%kw) {
    for @names -> $n {
      given $n {
        when Pair { self.references-values.push: $n.key.Str if $n.value }
        default   { self.references-values.push: $n.Str }
      }
    }
    for %kw.kv -> $k, $v { self.references-values.push: $k.Str if $v }
    self;
  }

  method readonly(Bool:D $on = True) {
    self.readonly-value = $on;
    self;
  }

  method lock($mode = True) {
    self.lock-value = $mode;
    self;
  }

  method extending(*@roles) {
    die 'extending requires at least one role' unless @roles.elems;
    my $obj = self;
    for @roles -> $role { $obj = $obj does $role }
    $obj;
  }

  method preload(*@names, *%kw) {
    self!collect-includes(self.preloads-values, @names, %kw);
    self;
  }

  method eager-load(*@names, *%kw) {
    self!collect-includes(self.eager-loads-values, @names, %kw);
    for self!flatten-include-names(@names, %kw) -> $n {
      next if self.references-values.first({ $_ eq $n });
      self.references-values.push: $n;
      self.left-outer-joins($n);
    }
    self;
  }

  method includes(*@names, *%kw) {
    self!collect-includes(self.pending-includes-values, @names, %kw);
    self;
  }

  method finalize-includes() {
    return unless self.pending-includes-values.elems;
    my @pending = self.pending-includes-values;
    self.pending-includes-values = ();

    for @pending -> $entry {
      my $top-name = ($entry ~~ Pair) ?? $entry.key.Str !! $entry.Str;
      if self!includes-should-eager-load($top-name) {
        unless self!already-listed(self.eager-loads-values, $top-name) {
          self.eager-loads-values.push: $entry;
        }
        my $needs-join = !self!join-added-for($top-name);
        unless self.references-values.first({ $_ eq $top-name }).defined {
          self.references-values.push: $top-name;
        }
        self.left-outer-joins($top-name) if $needs-join;
      } else {
        unless self!already-listed(self.preloads-values, $top-name) {
          self.preloads-values.push: $entry;
        }
      }
    }
  }

  method !join-added-for(Str:D $name --> Bool) {
    my $table-name = self!resolve-include-table($name);
    return False unless $table-name;
    for self.joins-values -> $j {
      next unless $j ~~ Str;
      return True if $j.contains(" $table-name ");
      return True if $j.ends-with(" $table-name");
    }
    False;
  }

  method !already-listed(@list, Str:D $name --> Bool) {
    for @list -> $e {
      my $n = ($e ~~ Pair) ?? $e.key.Str !! $e.Str;
      return True if $n eq $name;
    }
    False;
  }

  method !includes-should-eager-load(Str:D $name --> Bool) {
    return True if self.references-values.first({ $_ eq $name }).defined;

    my $table-name = self!resolve-include-table($name);
    return False unless $table-name;

    for self.where-values.kv -> $k, $v {
      return True if $k.starts-with($table-name ~ '.');
      return True if $k eq $table-name && $v ~~ Hash;
    }
    for self.where-not-values.kv -> $k, $v {
      return True if $k.starts-with($table-name ~ '.');
      return True if $k eq $table-name && $v ~~ Hash;
    }
    for self.order-values -> $o {
      next unless $o ~~ Str;
      return True if $o.contains($table-name ~ '.');
    }
    for self.having-values -> $h {
      next unless $h ~~ Str;
      return True if $h.contains($table-name ~ '.');
    }
    False;
  }

  method !resolve-include-table(Str:D $name --> Str) {
    my $stub = self.class-of.new(:id(0));
    my $spec = $stub.belongs-tos{$name}
            // $stub.has-manys{$name}
            // $stub.has-ones{$name}
            // $stub.habtms{$name};
    return $name without $spec;
    my $class = $stub.assoc-class-from-spec($spec);
    return $name if $class === Mu;
    Utils.table-name($class);
  }

  method !collect-includes(@target, @names, %kw) {
    for @names -> $n {
      given $n {
        when Pair { @target.push: $n }
        when Hash | Map {
          for $n.kv -> $k, $v { @target.push: ($k.Str => $v) }
        }
        when Iterable { self!collect-includes(@target, $n.list, {}) }
        default { @target.push: $n.Str }
      }
    }
    for %kw.kv -> $k, $v { @target.push: ($k.Str => $v) }
  }

  method !flatten-include-names(@names, %kw) {
    my @out;
    for @names -> $n {
      given $n {
        when Pair        { @out.push: $n.key.Str }
        when Hash | Map  { @out.append: $n.keys.map(*.Str) }
        when Iterable    { @out.append: self!flatten-include-names($n.list, {}) }
        default          { @out.push: $n.Str }
      }
    }
    @out.append: %kw.keys.map(*.Str);
    @out;
  }

  method having(*@parts, *%kw) {
    if %kw.elems {
      self.having-values.push: %kw.item;
      return self;
    }
    die 'having requires at least a SQL fragment' unless @parts.elems;
    if @parts.elems == 1 && @parts[0] ~~ Hash {
      self.having-values.push: @parts[0].item;
    } elsif @parts.elems == 1 && @parts[0] ~~ Str {
      self.having-values.push: @parts[0];
    } else {
      self.having-values.push: @parts.list;
    }
    self;
  }
}
