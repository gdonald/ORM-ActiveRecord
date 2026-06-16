
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migrate;
use ORM::ActiveRecord::Schema::WorkerDbs;
use ORM::ActiveRecord::Schema::Dumper;
use ORM::ActiveRecord::Schema::Cache;
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

  method !primary-connection {
    self!connections[0] // default-connection();
  }

  method !adapter-kind(--> Str) {
    given DB.shared(name => self!primary-connection).adapter.^name {
      when /Sqlite/ { 'sqlite' }
      when /Pg/     { 'pg' }
      when /MySql/  { 'mysql' }
      default       { 'unknown' }
    }
  }

  method schema-dump(Str:D :$path = 'db/schema.raku' --> Str) {
    my $migrate = self!primary-migrate;
    $migrate.check-migrations-table;

    my $dumper = SchemaDumper.new(
      adapter  => DB.shared(name => self!primary-connection).adapter,
      versions => $migrate.applied-versions,
    );

    my $content = $dumper.render-schema;
    $path.IO.spurt($content);
    $path;
  }

  method schema-load(Str:D :$path = 'db/schema.raku') {
    die "schema file not found: $path" unless $path.IO.e;

    my $conn = self!primary-connection;
    DB.set-shared(Nil, name => $conn);
    self!migrate-for($conn).reset(args => ['--yes', '--quiet']);

    my $schema = EVAL $path.IO.slurp;
    $schema.new.up;

    my $migrate = self!migrate-for($conn);
    $migrate.check-migrations-table;
    $migrate.add(version => ~$_) for $schema.new.versions;
  }

  method structure-dump(Str:D :$path = 'db/structure.sql' --> Str) {
    my $sql = self!structure-sql;
    $path.IO.spurt($sql);
    $path;
  }

  method !structure-sql(--> Str) {
    my $conn    = self!primary-connection;
    DB.set-shared(Nil, name => $conn);
    my $adapter = DB.shared(name => $conn).adapter;

    given self!adapter-kind {
      when 'sqlite' {
        my @stmts = $adapter.exec(
          "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY (type = 'table') DESC, name"
        ).map({ ~$_[0] ~ ';' });

        my @versions = self!migrate-for($conn).applied-versions;
        @stmts.append: @versions.map({ "INSERT INTO migrations (version) VALUES ('$_');" });

        @stmts.join("\n\n") ~ "\n";
      }
      when 'pg'    { self!native-structure-dump($conn, 'pg') }
      when 'mysql' { self!native-structure-dump($conn, 'mysql') }
      default      { "-- structure dump unsupported for this adapter\n" }
    }
  }

  method !native-structure-dump(Str:D $conn, Str:D $kind --> Str) {
    my %cfg = DB.read-config(:$!path, name => $conn, :$!env);
    my $name = %cfg<name> // %cfg<database>;

    my $proc;
    if $kind eq 'pg' {
      temp %*ENV<PGPASSWORD> = %cfg<password> // '';
      $proc = run 'pg_dump', '--schema-only', '--no-owner', '--no-privileges',
        '-h', (%cfg<host> // 'localhost'), '-p', (%cfg<port> // 5432).Str,
        '-U', (%cfg<user> // ''), $name, :out, :err;
    } else {
      $proc = run 'mysqldump', '--no-data', '--skip-comments',
        '-h', (%cfg<host> // '127.0.0.1'), '-P', (%cfg<port> // 3306).Str,
        '-u', (%cfg<user> // 'root'),
        ('--password=' ~ (%cfg<password> // '')), $name, :out, :err;
    }

    my $out = $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    $out || "-- structure dump produced no output (is the $kind client installed?)\n";
  }

  method schema-cache-dump(Str:D :$path = 'db/schema_cache.yml' --> Str) {
    my $conn = self!primary-connection;
    DB.set-shared(Nil, name => $conn);
    SchemaCache.new(adapter => DB.shared(name => $conn).adapter).dump-yaml(:$path);
    $path;
  }

  method schema-cache-clear(Str:D :$path = 'db/schema_cache.yml' --> Bool) {
    return False unless $path.IO.e;
    $path.IO.unlink;
    True;
  }
}
