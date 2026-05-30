use ORM::ActiveRecord::Schema::Migration;

class DropTouchFixtures is Migration {
  method up {
    for <tnitems tnshops> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
