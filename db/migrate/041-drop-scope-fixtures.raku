use ORM::ActiveRecord::Schema::Migration;

class DropScopeFixtures is Migration {
  method up {
    for <scarticles_sctags sctags scprofiles scarticles scauthors> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
