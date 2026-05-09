
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
        default { die "unscope: unknown scope kind '$kind'" }
      }
    }
    self;
  }

  method order(*@cols) {
    @!order.append: @cols.map({ .Str });
    self;
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
    );
  }

  method first {
    my @order = @!order.elems ?? @!order !! ('id',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order, distinct => $!distinct, group => @!group, having => @!having, from-source => $!from-source, from-alias => $!from-alias);
    $obj.make-readonly if $obj.defined && $!readonly;
    $obj;
  }

  method last {
    my @order = @!order.elems
      ?? @!order
      !! ('id DESC',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order, distinct => $!distinct, group => @!group, having => @!having, from-source => $!from-source, from-alias => $!from-alias);
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
