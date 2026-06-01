
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Support::Environment;

class DB is export {
  my %shared;
  my Bool $legacy-warned = False;

  has Adapter $.adapter handles *;
  has Str $.name = default-connection();

  submethod BUILD(Adapter :$adapter, Str :$name = default-connection()) {
    $!name = $name;

    if $adapter.defined {
      $!adapter = $adapter;
    } else {
      my %config = self.read-config(:$name);
      $!adapter = self!build-adapter(%config);
    }
  }

  # Process-wide shared connection, keyed by connection name. Use this
  # everywhere instead of `DB.new` — creating an anonymous DB per call relies
  # on GC-driven `dispose`, which races with in-flight `allrows` iteration in
  # DBDish::Pg and produces "No such method 'PQgetisnull' for invocant of type
  # 'Any'" errors.
  method shared(Str:D :$name = default-connection() --> DB) {
    %shared{$name} //= DB.new(:$name);
    %shared{$name};
  }

  # Test seam: swap a named shared singleton to point at a hand-built DB
  # (e.g. one wrapping a SqliteAdapter against `:memory:`). Pass `Nil` to
  # clear and force the next `.shared` to rebuild from config.
  method set-shared($db, Str:D :$name = default-connection() --> DB) {
    %shared{$name} = $db;
    $db;
  }

  method adapter-class-for(%config) {
    my $kind = (%config<adapter> // 'pg').lc;
    given $kind {
      when 'pg' | 'postgres' | 'postgresql' { PgAdapter }
      when 'sqlite' | 'sqlite3'             { SqliteAdapter }
      when 'mysql' | 'mysql2' | 'mariadb'   { MySqlAdapter }
      default { die "DB: unsupported adapter '$kind'" }
    }
  }

  method !build-adapter(%config) {
    my $cls = self.adapter-class-for(%config);
    given $cls {
      when PgAdapter {
        PgAdapter.new(
          schema   => %config<schema>   // 'public',
          host     => %config<host>     // 'localhost',
          database => %config<name>     // %config<database>,
          user     => %config<user>     // '',
          password => %config<password> // '',
        );
      }
      when SqliteAdapter {
        SqliteAdapter.new(
          database => %config<name> // %config<database> // ':memory:',
        );
      }
      when MySqlAdapter {
        MySqlAdapter.new(
          host     => %config<host>     // 'localhost',
          port     => (%config<port> // 3306).Int,
          database => %config<name>     // %config<database>,
          user     => %config<user>     // 'root',
          password => %config<password> // '',
          socket   => %config<socket>   // '',
        );
      }
    }
  }

  method read-config(Str :$path = 'config/application.json',
                     Str :$name = default-connection(),
                     Str :$env  = current-env('development')) {
    my %config = self!raw-config(:$path, :$name, :$env);

    # behave hands each parallel worker a slot in 0 .. count-1 via
    # BEHAVE_WORKER_INDEX/BEHAVE_WORKER_COUNT; suffix the database by that slot
    # so concurrent workers never share one. Serial / non-behave runs use the
    # base database.
    %config = apply-worker-suffix(%config, worker-index())
      if per-worker-dbs-active();

    %config;
  }

  # Connection names configured for the active environment. Legacy flat config
  # and an absent/empty config yield just the primary connection; primary is
  # always included (it may be supplied via DATABASE_URL).
  method connection-names(Str :$path = 'config/application.json',
                          Str :$env  = current-env('development') --> List) {
    return (default-connection(),) unless $path.IO.e;

    my $fh = open $path, :r;
    my $contents = $fh.slurp-rest;
    $fh.close;

    my $json = from-json($contents);
    return (default-connection(),) without $json;
    return (default-connection(),) if $json<db>:exists;

    my @names = ($json{$env} // %()).hash.keys.grep(* ne 'parallel').sort;
    @names.unshift(default-connection()) unless default-connection() ∈ @names;
    @names.List;
  }

  # Per-environment parallel worker count (the `parallel` key). Only the test
  # environment is expected to set it; everywhere else it defaults to 1.
  method env-parallel(Str :$path = 'config/application.json',
                      Str :$env  = current-env('development') --> Int) {
    return 1 unless $path.IO.e;

    my $fh = open $path, :r;
    my $contents = $fh.slurp-rest;
    $fh.close;

    my $json = from-json($contents);
    return 1 without $json;
    return 1 if $json<db>:exists;

    (($json{$env} // %())<parallel> // 1).Int;
  }

  # DATABASE_URL overrides the active environment's primary connection; every
  # other named connection is resolved from config/application.json.
  method !raw-config(Str :$path, Str :$name, Str :$env) {
    if $name eq default-connection() && (my $url = %*ENV<DATABASE_URL>) {
      return parse-database-url($url);
    }

    self!file-connection(:$path, :$name, :$env);
  }

  method !file-connection(Str :$path, Str :$name, Str :$env) {
    return %() unless $path.IO.e;

    my $fh = open $path, :r;
    my $contents = $fh.slurp-rest;
    $fh.close;

    my $json = from-json($contents);
    return %() without $json;

    # Legacy flat shape: { "db": {...} } promotes to the primary connection
    # of every environment. Deprecated; the per-env named-connection shape
    # ({ "test": { "primary": {...} } }) is the supported form.
    if $json<db>:exists {
      self!warn-legacy;
      return $name eq default-connection() ?? $json<db>.hash !! %();
    }

    my %connections = ($json{$env} // %()).hash;
    (%connections{$name} // %()).hash;
  }

  method !warn-legacy {
    return if $legacy-warned;
    $legacy-warned = True;
    return if %*ENV<DISABLE-SQL-LOG>;
    note "ORM: flat 'db' config is deprecated; use per-environment named connections (see docs)";
  }
}
