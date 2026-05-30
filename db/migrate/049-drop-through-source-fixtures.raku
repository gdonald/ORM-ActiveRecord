use ORM::ActiveRecord::Schema::Migration;

class DropThroughSourceFixtures is Migration {
  method up {
    for <thsubs thmags thusers> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
