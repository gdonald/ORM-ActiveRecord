
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Utils;

class Query is export {
  has Mu $!class;
  has Str $!table;
  has Hash $!params;
  has @!fields of Field;
  has @!order;
  has Int $!limit  = 0;
  has Int $!offset = 0;
  has @!select;

  submethod BUILD(Mu:U :$!class, Hash:D :$!params) {
    $!table = Utils.table-name($!class);
    @!fields = DB.shared.get-fields(:$!table).map({ Field.new(:name($_[0]), :type($_[1])) });
  }

  method where(Hash:D $more) {
    for $more.kv -> $k, $v { $!params{$k} = $v }
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
    DB.shared.get-objects(
      :$!table, :$!class, :@!fields,
      where => $!params, order => @!order,
      limit => $!limit, offset => $!offset,
    );
  }

  method all {
    self.perform;
  }

  method count {
    DB.shared.count-records(:$!table, where => $!params);
  }

  method first {
    my @order = @!order.elems ?? @!order !! ('id',);
    DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, :@order);
  }

  method last {
    my @order = @!order.elems
      ?? @!order
      !! ('id DESC',);
    DB.shared.get-object(:$!table, :$!class, :@!fields, where => $!params, :@order);
  }

  method pluck(*@cols) {
    my @names = @cols.elems ?? @cols.map({ .Str }) !! @!select.elems ?? @!select !! die 'pluck requires at least one column';
    my @fields = @names.map({ Field.new(:name($_), :type('character varying')) });
    my @rows = DB.shared.exec-stmt(
      DB.shared.build-select(
        :$!table, :@fields, where => $!params,
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
