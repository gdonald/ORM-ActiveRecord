use ORM::ActiveRecord::Schema::Migration;

class DropAutosaveFixtures is Migration {
  method up {
    for <aschilds asparents> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
