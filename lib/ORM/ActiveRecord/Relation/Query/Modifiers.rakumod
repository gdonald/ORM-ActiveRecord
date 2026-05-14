
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
        when 'where'    { self.where-values = {}; self.where-not-values = {} }
        when 'order'    { self.order-values = () }
        when 'limit'    { self.limit-value = 0 }
        when 'offset'   { self.offset-value = 0 }
        when 'select'   { self.select-values = () }
        when 'distinct' { self.distinct-value = False }
        when 'group'    { self.group-values = () }
        when 'having'   { self.having-values = () }
        when 'from'       { self.from-source = Str; self.from-alias = Str }
        when 'references' { self.references-values = () }
        when 'readonly'   { self.readonly-value = False }
        when 'joins'      { self.joins-values = () }
        when 'with'       { self.ctes-values = () }
        when 'annotate'   { self.annotations-values = () }
        when 'optimizer-hints' { self.optimizer-hints-values = () }
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

  method references(*@names) {
    self.references-values.append: @names.map({ .Str });
    self;
  }

  method readonly(Bool:D $on = True) {
    self.readonly-value = $on;
    self;
  }

  method extending(*@roles) {
    die 'extending requires at least one role' unless @roles.elems;
    my $obj = self;
    for @roles -> $role { $obj = $obj does $role }
    $obj;
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
