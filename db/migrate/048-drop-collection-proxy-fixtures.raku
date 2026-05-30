use ORM::ActiveRecord::Schema::Migration;

class DropCollectionProxyFixtures is Migration {
  method up {
    for <cpcomments cpposts cpauthors> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
