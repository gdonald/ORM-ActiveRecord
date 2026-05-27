use lib 'lib';
use BDD::Behave;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migrate;

my $sqlite;
my $migrate;
my $prior-db;

my &group = $has-sqlite ?? &describe !! &xdescribe;

group 'migration on a fresh SQLite db', :tag<destructive>, :order<defined>, {
  if !$has-sqlite { pending 'DBDish::SQLite not installed in this environment'; }

  before-all {
    if $has-sqlite {
      $prior-db = DB.shared;
      $sqlite   = SqliteAdapter.new(database => ':memory:');
      DB.set-shared(DB.new(adapter => $sqlite));
      $migrate  = Migrate.new(:args([]));
    }
  }

  after-all {
    if $has-sqlite {
      DB.set-shared($prior-db // Nil);
    }
  }

  context 'before the migrations table is created', {
    it 'migrations-table-exists is False', {
      expect($migrate.migrations-table-exists).to.be-falsy;
    }
  }

  context 'after create-migrations-table', :order<defined>, {
    before-all {
      if $has-sqlite {
        $migrate.create-migrations-table;
      }
    }

    it 'installs the migrations table', {
      expect($migrate.migrations-table-exists).to.be-truthy;
    }

    it 'lists migrations in get-table-names', {
      expect('migrations' (elem) $sqlite.get-table-names).to.be-truthy;
    }

    it 'has an id column', {
      my @cols = $sqlite.get-fields(table => 'migrations').map({ $_[0] });
      expect('id' (elem) @cols).to.be-truthy;
    }

    it 'has a version column', {
      my @cols = $sqlite.get-fields(table => 'migrations').map({ $_[0] });
      expect('version' (elem) @cols).to.be-truthy;
    }

    it 'last is empty before any version recorded', {
      expect($migrate.last).to.eq('');
    }
  }

  context 'after add(version)', :order<defined>, {
    it 'last reads back the inserted version', {
      $migrate.add(version => '20260101000001');
      expect($migrate.last).to.eq('20260101000001');
    }

    it 'last returns the most-recent version after a second add', {
      $migrate.add(version => '20260201000002');
      expect($migrate.last).to.eq('20260201000002');
    }
  }

  context 'after rm(version)', :order<defined>, {
    it 'removes the matching row', {
      $migrate.rm(version => '20260201000002');
      expect($migrate.last).to.eq('20260101000001');
    }

    it 'clears history when removing the last row', {
      $migrate.rm(version => '20260101000001');
      expect($migrate.last).to.eq('');
    }
  }

  context 'after add/rm cycle', {
    it 'migrations-table-exists is still True', {
      expect($migrate.migrations-table-exists).to.be-truthy;
    }
  }
}
