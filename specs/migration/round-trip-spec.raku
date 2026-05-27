use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

my $canonical-shared  = DB.shared;
my $canonical-adapter = $canonical-shared.adapter;
my $has-db = $canonical-adapter.defined && $canonical-adapter.is-connected;

my @canonical-tables;
my @after-up;
my $original-shared;
my $iso-db;

my &group = $has-db ?? &describe !! &xdescribe;

# Migrate.run EVALs each `db/migrate/*.raku` once per process, so this spec
# uses an isolated in-memory SQLite DB for the single migrate-up pass.
# Reset is covered separately by specs/query/reset-spec.raku.

group 'migration round-trip', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all {
    if $has-db {
      @canonical-tables = $canonical-adapter.get-table-names.list
        .grep({ $_ ne 'migrations' }).sort;

      $original-shared = DB.shared;
      $iso-db = DB.new(adapter => SqliteAdapter.new(database => ':memory:'));
      DB.set-shared($iso-db);
    }
  }

  after-all {
    if $has-db {
      DB.set-shared($original-shared) if $original-shared.defined;
      $original-shared = Nil;
      $iso-db = Nil;
    }
  }

  context 'starting iso schema', {
    it 'is empty before any migration', {
      expect($iso-db.get-table-names.elems).to.eq(0);
    }
  }

  context 'migrate up on empty iso DB', :order<defined>, {
    before-all {
      if $has-db {
        Migrate.new(:args([])).run;
        @after-up = $iso-db.get-table-names.list
          .grep({ $_ ne 'migrations' }).sort;
      }
    }

    it 'creates the same set of tables as the canonical shared DB', {
      expect(@after-up.join(',')).to.eq(@canonical-tables.join(','));
    }

    it 'creates the migrations bookkeeping table', {
      expect('migrations' (elem) $iso-db.get-table-names.list).to.be-truthy;
    }
  }
}
