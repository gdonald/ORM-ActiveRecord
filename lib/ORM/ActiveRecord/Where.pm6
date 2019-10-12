
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Utils;

class Where is export {
  has Mu $!class;
  has Hash $!params;
  has Bool $!performed = False;
  has @.objects;

  submethod BUILD(Mu:U :$!class, Hash:D :$!params) {

  }

  method perform {
    return if $!performed;
    $!performed = True;

    my $table = Utils.table-name($!class);
    my @fields = DB.new.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %where = $!params;

    @!objects = DB.new.get-objects(:$table, :$!class, :@fields, :%where);
  }

  method count {
    self.perform;
    @!objects.elems;
  }

  method first {
    self.perform;
    @!objects.first;
  }
}
