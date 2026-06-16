
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migrate;
use ORM::ActiveRecord::Schema::WorkerDbs;
use ORM::ActiveRecord::Support::Environment;

# The `ar db:*` tasks. Database existence (create / drop) fans out over every
# configured connection of the active environment; migration-state tasks
# (version, status, rollback, ...) act on the primary connection. A migration
# path can be injected for tests.
class DbTasks is export {
  has Str $.path           = 'config/application.json';
  has Str $.env            = current-env('development');
  has Str $.seeds          = 'db/seeds.raku';
  has Str $.migration-path;
  has     $.out            = $*OUT;
  has     $.err            = $*ERR;

  method !migrate-for(Str:D $conn --> Migrate) {
    my %opts = connection => $conn;
    %opts<migration-path> = $!migration-path if $!migration-path.defined;
    Migrate.new(|%opts);
  }

  method !connections { DB.connection-names(:$!path, :$!env) }

  method !primary-migrate(--> Migrate) {
    my $conn = self!connections[0] // default-connection();
    DB.set-shared(Nil, name => $conn);
    self!migrate-for($conn);
  }

  method !each-connection(&body) {
    my @results;
    for self!connections -> $conn {
      DB.set-shared(Nil, name => $conn);
      @results.push: body($conn, self!migrate-for($conn));
      DB.set-shared(Nil, name => $conn);
    }
    @results;
  }

  method create {
    create-test-databases(:$!path, :$!env);
  }

  method drop {
    drop-test-databases(:$!path, :$!env);
  }

  method migrate {
    self!each-connection(-> $conn, $migrate { $migrate.run });
  }

  method migrate-to(Str:D $version) {
    self!each-connection(-> $conn, $migrate { $migrate.migrate-to($version) });
  }

  method migrate-up(Str:D $version --> Bool) {
    self!each-connection(-> $conn, $migrate { $migrate.run-version($version, 'up') }).head;
  }

  method migrate-down(Str:D $version --> Bool) {
    self!each-connection(-> $conn, $migrate { $migrate.run-version($version, 'down') }).head;
  }

  method redo(Int:D :$step = 1) {
    self!each-connection(-> $conn, $migrate { $migrate.migrate-redo($step) });
  }

  method rollback(Int:D :$step = 1) {
    self!each-connection(-> $conn, $migrate {
      $migrate.check-migrations-table;
      $migrate.migrate(['down', $step]);
    });
  }

  method version(--> Str) {
    my $migrate = self!primary-migrate;
    $migrate.check-migrations-table;

    my $version = $migrate.current-version;
    $!out.say('Current version: ' ~ ($version eq '' ?? '0' !! $version));
    $version;
  }

  method status(--> List) {
    my @rows = self!primary-migrate.status-rows;
    for @rows -> %row {
      $!out.say(sprintf('%-4s  %s  %s', %row<status>, %row<version>, %row<name>));
    }
    @rows.List;
  }

  method abort-if-pending(--> Int) {
    my $migrate = self!primary-migrate;
    $migrate.check-migrations-table;

    if $migrate.is-pending {
      $!err.say('pending migrations: ' ~ $migrate.pending-versions.join(', '));
      return 1;
    }

    $!out.say('no pending migrations');
    0;
  }

  method seed(--> Bool) {
    unless $!seeds.IO.e {
      $!out.say("no seeds file at $!seeds");
      return False;
    }

    DB.set-shared(Nil);
    EVAL $!seeds.IO.slurp;
    True;
  }

  method setup {
    self.create;
    self.migrate;
    self.seed;
  }

  method reset {
    self.drop;
    self.setup;
  }

  method prepare {
    self.create;

    my $was-new = !self!primary-migrate.migrations-table-exists;
    self.migrate;
    self.seed if $was-new;
  }

  method test-prepare {
    my $tasks = self.clone(:env('test'));
    $tasks.create;
    $tasks.migrate;
  }
}
