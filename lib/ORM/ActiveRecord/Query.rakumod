
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
        when 'where'  { $!params = {}; $!not-params = {} }
        when 'order'  { @!order = () }
        when 'limit'  { $!limit = 0 }
        when 'offset' { $!offset = 0 }
        when 'select' { @!select = () }
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

  method !projection-fields {
    return @!fields unless @!select.elems;
    my %by-name = @!fields.map({ .name => $_ });
    @!select.map({
      %by-name{$_} // Field.new(:name($_), :type('character varying'))
    });
  }

  method perform {
    my @or-groups = self.or-groups-payload;
    DB.shared.get-objects(
      :$!table, :$!class, :@!fields,
      where => $!params, where-not => $!not-params, :@or-groups,
      order => @!order,
      limit => $!limit, offset => $!offset,
    );
  }

  method all {
    self.perform;
  }

  method count {
    my @or-groups = self.or-groups-payload;
    DB.shared.count-records(:$!table, where => $!params, where-not => $!not-params, :@or-groups);
  }

  method first {
    my @order = @!order.elems ?? @!order !! ('id',);
    my @or-groups = self.or-groups-payload;
    DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order);
  }

  method last {
    my @order = @!order.elems
      ?? @!order
      !! ('id DESC',);
    my @or-groups = self.or-groups-payload;
    DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, where-not => $!not-params, :@or-groups, :@order);
  }

  method pluck(*@cols) {
    my @names = @cols.elems ?? @cols.map({ .Str }) !! @!select.elems ?? @!select !! die 'pluck requires at least one column';
    my @fields = @names.map({ Field.new(:name($_), :type('character varying')) });
    my @or-groups = self.or-groups-payload;
    my @rows = DB.shared.exec-stmt(
      DB.shared.build-select(
        :$!table, :@fields, where => $!params, where-not => $!not-params, :@or-groups,
        order => @!order, limit => $!limit, offset => $!offset,
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
