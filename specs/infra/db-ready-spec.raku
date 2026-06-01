use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Schema::DbReady;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

# These assert base behaviour; clear any per-worker overlay from the harness.
%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

my &group = $has-sqlite ?? &describe !! &xdescribe;

describe 'database-status', {
  it 'reports sqlite :memory: as ready', {
    expect(database-status({ adapter => 'sqlite', name => ':memory:' })).to.eq('ready');
  }
}

group 'database-status (on-disk sqlite)', :tag<destructive>, {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  my @paths;
  after-all { .IO.unlink for @paths.grep(*.IO.e) }

  it 'reports a non-existent file as missing', {
    my $path = $*TMPDIR.add("dbr-missing-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;

    expect(database-status({ adapter => 'sqlite', name => $path })).to.eq('missing');
  }

  it 'reports an empty file with no migrations table as pending', {
    my $path = $*TMPDIR.add("dbr-pending-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    @paths.push: $path;
    $path.IO.spurt('');

    expect(database-status({ adapter => 'sqlite', name => $path })).to.eq('pending');
  }

  it 'reports a fully migrated database as ready', {
    my $path = $*TMPDIR.add("dbr-ready-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    @paths.push: $path;

    my $adapter = SqliteAdapter.new(database => $path);
    DB.set-shared(DB.new(adapter => $adapter));
    LEAVE { DB.set-shared(Nil) }
    Migrate.new(:args([])).run;

    expect(database-status({ adapter => 'sqlite', name => $path })).to.eq('ready');
  }
}
