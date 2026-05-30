use ORM::ActiveRecord::Schema::Migration;

class DropCounterCacheFixtures is Migration {
  method up {
    for <ccbooks ccteams ccshops> -> $t {
      self.drop-table-if-exists: $t;
    }
  }

  method down {
    die X::IrreversibleMigration.new;
  }
}
