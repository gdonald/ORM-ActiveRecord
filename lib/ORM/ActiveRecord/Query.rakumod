
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Utils;

class Query is export {
  has Mu $!class;
  has Str $!table;
  has Hash $!params;
  has Hash $!not-params;
  has @!or-relations;
  has @!fields of Field;
  has @!order;
  has Int $!limit  = 0;
  has Int $!offset = 0;
  has @!select;
  has Bool $!distinct = False;
  has @!group;
  has @!having;
  has Str $!from-source;
  has Str $!from-alias;
  has @!references;
  has Bool $!readonly = False;
  has @!joins;

  submethod BUILD(Mu:U :$!class, Hash:D :$!params) {
    $!table = Utils.table-name($!class);
    $!not-params = {};
    @!fields = DB.shared.get-fields(:$!table).map({ Field.new(:name($_[0]), :type($_[1])) });
  }

  method where-values     { $!params }
  method where-not-values { $!not-params }
  method or-relations     { @!or-relations }
  method order-values     { @!order }
  method limit-value      { $!limit }
  method offset-value     { $!offset }
  method select-values    { @!select }
  method distinct-value   { $!distinct }
  method group-values     { @!group }
  method having-values    { @!having }
  method from-source      { $!from-source }
  method from-alias       { $!from-alias }
  method references-values { @!references }
  method readonly-value    { $!readonly }
  method joins-values      { @!joins }

  method or-groups-payload {
    @!or-relations.map({
      %( where => $_.where-values, where-not => $_.where-not-values )
    });
  }

  method where(Hash:D $more = {}) {
    for $more.kv -> $k, $v { $!params{$k} = $v }
    self;
  }

  method not(Hash:D $more) {
    for $more.kv -> $k, $v { $!not-params{$k} = $v }
    self;
  }

  method rewhere(Hash:D $more) {
    for $more.kv -> $k, $v {
      $!params{$k}:delete;
      $!not-params{$k}:delete;
      $!params{$k} = $v;
    }
    self;
  }

  method or(Query:D $other) {
    @!or-relations.push: $other;
    self;
  }

  method and(Query:D $other) {
    for $other.where-values.kv -> $k, $v {
      $!not-params{$k}:delete;
      $!params{$k} = $v;
    }
    for $other.where-not-values.kv -> $k, $v {
      $!params{$k}:delete;
      $!not-params{$k} = $v;
    }
    self;
  }

  method merge(Query:D $other) {
    for $other.where-values.kv -> $k, $v {
      $!not-params{$k}:delete;
      $!params{$k} = $v;
    }
    for $other.where-not-values.kv -> $k, $v {
      $!params{$k}:delete;
      $!not-params{$k} = $v;
    }
    @!order.append: $other.order-values if $other.order-values.elems;
    $!limit  = $other.limit-value  if $other.limit-value  > 0;
    $!offset = $other.offset-value if $other.offset-value > 0;
    @!select.append: $other.select-values if $other.select-values.elems;
    $!distinct = True if $other.distinct-value;
    @!group.append: $other.group-values if $other.group-values.elems;
    @!having.append: $other.having-values if $other.having-values.elems;
    if $other.from-source.defined {
      $!from-source = $other.from-source;
      $!from-alias  = $other.from-alias;
    }
    @!references.append: $other.references-values if $other.references-values.elems;
    $!readonly = True if $other.readonly-value;
    @!joins.append: $other.joins-values if $other.joins-values.elems;
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
              $!params{$c}:delete;
              $!not-params{$c}:delete;
            }
          }
          default { die "unscope: '$kind' does not accept a column argument" }
        }
      }
    }
    for @all-kinds.unique -> $kind {
      given $kind {
        when 'where'    { $!params = {}; $!not-params = {} }
        when 'order'    { @!order = () }
        when 'limit'    { $!limit = 0 }
        when 'offset'   { $!offset = 0 }
        when 'select'   { @!select = () }
        when 'distinct' { $!distinct = False }
        when 'group'    { @!group = () }
        when 'having'   { @!having = () }
        when 'from'       { $!from-source = Str; $!from-alias = Str }
        when 'references' { @!references = () }
        when 'readonly'   { $!readonly = False }
        when 'joins'      { @!joins = () }
        default { die "unscope: unknown scope kind '$kind'" }
      }
    }
    self;
  }

  method order(*@cols, *%kw) {
    for @cols -> $c {
      given $c {
        when Pair { @!order.push: self!format-direction(.key, .value) }
        when Str  { @!order.push: $c }
        default   { @!order.push: $c.Str }
      }
    }
    for %kw.kv -> $k, $v { @!order.push: self!format-direction($k, $v) }
    self;
  }

  method reorder(*@cols, *%kw) {
    @!order = ();
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
    @!order.push: ((@parts.join(' '), |@values).List);
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
    $!limit = $n;
    self;
  }

  method offset(Int:D $n) {
    $!offset = $n;
    self;
  }

  method select(*@cols) {
    @!select.append: @cols.map({ .Str });
    self;
  }

  method distinct(Bool:D $on = True) {
    $!distinct = $on;
    self;
  }

  method group(*@cols) {
    @!group.append: @cols.map({ .Str });
    self;
  }

  method regroup(*@cols) {
    @!group = @cols.map({ .Str });
    self;
  }

  method from($source, Str $alias?) {
    $!from-source = $source.Str;
    $!from-alias = $alias.defined ?? $alias.Str !! Str;
    self;
  }

  method references(*@names) {
    @!references.append: @names.map({ .Str });
    self;
  }

  method readonly(Bool:D $on = True) {
    $!readonly = $on;
    self;
  }

  method extending(*@roles) {
    die 'extending requires at least one role' unless @roles.elems;
    my $obj = self;
    for @roles -> $role { $obj = $obj does $role }
    $obj;
  }

  method joins(*@args, *%kw) {
    self!collect-joins('INNER JOIN', @args, %kw);
    self;
  }

  method left-outer-joins(*@args, *%kw) {
    self!collect-joins('LEFT OUTER JOIN', @args, %kw);
    self;
  }

  method !collect-joins(Str:D $kind, @args, %kw) {
    for @args -> $a {
      self!add-join-arg($kind, $a, $!class, $!table);
    }
    for %kw.kv -> $k, $v {
      self!add-named-join($kind, $k, $v, $!class, $!table);
    }
  }

  method !add-named-join(Str:D $kind, $k, $v, Mu $base-class, Str $base-table) {
    my ($child-class, $child-table) = self!add-assoc-join($kind, $k.Str, $base-class, $base-table);
    self!add-join-arg($kind, $v, $child-class, $child-table) unless $v === True;
  }

  method !add-join-arg(Str:D $kind, $arg, Mu $base-class, Str $base-table) {
    given $arg {
      when Pair {
        self!add-named-join($kind, $arg.key, $arg.value, $base-class, $base-table);
      }
      when Hash {
        for $arg.kv -> $k, $v {
          self!add-named-join($kind, $k, $v, $base-class, $base-table);
        }
      }
      when Iterable {
        for $arg.list -> $sub { self!add-join-arg($kind, $sub, $base-class, $base-table) }
      }
      when Str {
        if $arg.contains(' ') || $arg.contains("\t") || $arg.uc.contains('JOIN') {
          @!joins.push: $arg;
        } else {
          self!add-assoc-join($kind, $arg, $base-class, $base-table);
        }
      }
      when Bool { }
      default {
        self!add-assoc-join($kind, $arg.Str, $base-class, $base-table);
      }
    }
  }

  method !add-assoc-join(Str:D $kind, Str:D $name, Mu $base-class, Str $base-table) {
    my $stub = $base-class.new(:id(0));
    if $stub.belongs-tos{$name}:exists {
      my $other-class = $stub.belongs-tos{$name}{'class'};
      my $other-table = Utils.table-name($other-class);
      my $fkey = $name ~ '_id';
      @!joins.push: "$kind $other-table ON $other-table.id = $base-table.$fkey";
      return ($other-class, $other-table);
    }
    if $stub.has-manys{$name}:exists {
      my $hm = $stub.has-manys{$name};
      if $hm{'through'}:exists {
        my $through-name = $hm{'through'}.key.Str;
        my ($mid-class, $mid-table) = self!add-assoc-join($kind, $through-name, $base-class, $base-table);
        my $singular = Utils.singular($name);
        my $mid-stub = $mid-class.new(:id(0));
        if $mid-stub.belongs-tos{$singular}:exists {
          my $other-class = $mid-stub.belongs-tos{$singular}{'class'};
          my $other-table = Utils.table-name($other-class);
          my $fkey = $singular ~ '_id';
          @!joins.push: "$kind $other-table ON $other-table.id = $mid-table.$fkey";
          return ($other-class, $other-table);
        }
        die "joins: cannot resolve has_many :through '$name' on " ~ $base-class.^name;
      }
      if $hm{'class'}:exists {
        my $other-class = $hm{'class'};
        my $other-table = Utils.table-name($other-class);
        my $fkey = Utils.to-foreign-key($base-table);
        @!joins.push: "$kind $other-table ON $other-table.$fkey = $base-table.id";
        return ($other-class, $other-table);
      }
    }
    die "joins: unknown association '$name' on " ~ $base-class.^name;
  }

  method having(*@parts) {
    die 'having requires at least a SQL fragment' unless @parts.elems;
    if @parts.elems == 1 && @parts[0] ~~ Str {
      @!having.push: @parts[0];
    } else {
      @!having.push: @parts.list;
    }
    self;
  }

  method !projection-fields {
    return @!fields unless @!select.elems;
    my %by-name = @!fields.map({ .name => $_ });
    @!select.map({
      %by-name{$_} // Field.new(:name($_), :type('character varying'))
    });
  }

  method perform {
    my @or-groups = self.or-groups-payload;
    my @objects = DB.shared.get-objects(
      :$!table, :$!class, :@!fields,
      where => $!params, where-not => $!not-params, :@or-groups,
      order => @!order,
      limit => $!limit, offset => $!offset,
      distinct => $!distinct,
      group => @!group, having => @!having,
      from-source => $!from-source, from-alias => $!from-alias,
      joins => @!joins,
    );
    if $!readonly {
      .make-readonly for @objects;
    }
    @objects;
  }

  method all {
    self.perform;
  }

  method count {
    my @or-groups = self.or-groups-payload;
    DB.shared.count-records(
      :$!table, where => $!params, where-not => $!not-params, :@or-groups,
      distinct => $!distinct, select => @!select,
      group => @!group, having => @!having,
      from-source => $!from-source, from-alias => $!from-alias,
      joins => @!joins,
    );
  }

  method first {
    my @order = @!order.elems ?? @!order !! ('id',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order, distinct => $!distinct, group => @!group, having => @!having, from-source => $!from-source, from-alias => $!from-alias, joins => @!joins);
    $obj.make-readonly if $obj.defined && $!readonly;
    $obj;
  }

  method last {
    my @order = @!order.elems
      ?? @!order
      !! ('id DESC',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order, distinct => $!distinct, group => @!group, having => @!having, from-source => $!from-source, from-alias => $!from-alias, joins => @!joins);
    $obj.make-readonly if $obj.defined && $!readonly;
    $obj;
  }

  method pluck(*@cols) {
    my @names = @cols.elems ?? @cols.map({ .Str }) !! @!select.elems ?? @!select !! die 'pluck requires at least one column';
    my @fields = @names.map({ Field.new(:name($_), :type('character varying')) });
    my @or-groups = self.or-groups-payload;
    my @rows = DB.shared.exec-stmt(
      DB.shared.build-select(
        :$!table, :@fields, where => $!params, where-not => $!not-params, :@or-groups,
        order => @!order, limit => $!limit, offset => $!offset,
        distinct => $!distinct,
        group => @!group, having => @!having,
        from-source => $!from-source, from-alias => $!from-alias,
        joins => @!joins,
      )
    );
    if @names.elems == 1 {
      @rows.map({ $_[0] });
    } else {
      @rows.map({ $_.list });
    }
  }

  method ids {
    self.pluck('id').map({ .Int });
  }

  method exists {
    self.count > 0;
  }
}
