
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Utils;

class Query is export {
  has Mu $!class;
  has Str $!table;
  has Hash $!params;
  has @!fields of Field;

  submethod BUILD(Mu:U :$!class, Hash:D :$!params) {
    $!table = Utils.table-name($!class);
    @!fields = DB.new.get-fields(:$!table).map({ Field.new(:name($_[0]), :type($_[1])) });
  }

  method perform {
    DB.new.get-objects(:$!table, :$!class, :@!fields, :where($!params));
  }

  method all {
    self.perform;
  }

  method count {
    DB.new.count-records(:$!table, :where($!params));
  }

  method first {
    my @order = <id>;
    DB.new.get-object(:$!table, :$!class, :@!fields, :where($!params), :@order)
  }
}
