use ORM::ActiveRecord::Schema::Migration;

class DropQueryConstraintsFixtures is Migration {
  method up {
    for <qcdocs qcorgs> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
