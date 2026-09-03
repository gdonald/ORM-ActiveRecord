
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::Connection::Pool;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Support::Environment;
use ORM::ActiveRecord::Instrumentation::QueryLogs;
use ORM::ActiveRecord::Instrumentation::LogSubscriber;
use ORM::ActiveRecord::Support::Log;

# When an async query runs on a worker thread it checks out a dedicated pooled
# connection and binds it here, so the whole call chain on that thread (the
# SELECT and the object instantiation) uses that connection instead of the
# shared one. Unset (undefined) on the main thread.
PROCESS::<$AR-DB-OVERRIDE> = Nil;

# A request-scoped registry (see Connection::Registry) that hands each named
# connection one pooled connection for the life of a request, checked out on
# first use and returned when the request ends. A web server binds this per
# request; unset outside one, where models fall back to the shared connection.
PROCESS::<$AR-CONNECTION-REGISTRY> = Nil;

class DB is export {
  # The named shared connections, held as an immutable Map that is replaced
  # wholesale on write. A reader takes no lock, since the Map it reads is never
  # mutated in place; a writer builds the next Map under the lock. `shared` is
  # reached through `DB.current` on essentially every model and query
  # operation, so taking a process-wide lock there put one on every row.
  my $shared = Map.new;
  my Lock $shared-lock = Lock.new;
  my Bool $legacy-warned = False;

  has Adapter $.adapter handles *;
  has Str $.name = default-connection();
  has %!config;
  has ConnectionPool $!pool;

  submethod BUILD(Adapter :$adapter, Str :$name = default-connection()) {
    $!name = $name;

    if $adapter.defined {
      $!adapter = $adapter;
    } else {
      %!config  = self.read-config(:$name);
      $!adapter = self!build-adapter(%!config);
    }
  }

  # Build a fresh, connected adapter from this connection's config. Used by the
  # pool to add connections; each is a full adapter with its own driver handle.
  method build-connection(--> Adapter) {
    my %config = %!config.elems ?? %!config !! self.read-config(:name($!name));
    self!build-adapter(%config);
  }

  # A lazily-built connection pool for this named connection, sized from the
  # config's `pool` key (and `min-threads` / `checkout-timeout` / etc.).
  method pool(--> ConnectionPool) {
    $!pool //= self!build-pool;
  }

  method with-connection(&block) {
    self.pool.with-connection(&block);
  }

  method cache(&block)       { $!adapter.cache(&block) }
  method uncached(&block)    { $!adapter.uncached(&block) }
  method clear-query-cache   { $!adapter.clear-query-cache }
  method enable-query-cache  { $!adapter.enable-query-cache }
  method disable-query-cache { $!adapter.disable-query-cache }
  method query-cache-enabled { $!adapter.query-cache-enabled }

  method !build-pool(--> ConnectionPool) {
    my %config = %!config.elems ?? %!config !! self.read-config(:name($!name));

    my $size              = (self!cfg-num(%config, 'pool', 'size', 'max-threads', 'max_threads') // 5).Int;
    my $min               = (self!cfg-num(%config, 'min-threads', 'min_threads', 'min') // 0).Int;
    my $checkout-timeout  =  self!cfg-num(%config, 'checkout-timeout', 'checkout_timeout') // 5;
    my $idle-timeout      =  self!cfg-num(%config, 'idle-timeout', 'idle_timeout') // 0;
    my $reaping-frequency =  self!cfg-num(%config, 'reaping-frequency', 'reaping_frequency') // 0;
    my $verify-timeout    =  self!cfg-num(%config, 'verify-timeout', 'verify_timeout') // 0;
    my $verify-idle-after =  self!cfg-num(%config, 'verify-idle-after', 'verify_idle_after') // 5;

    ConnectionPool.new(
      builder => { self.build-connection },
      :$size, :$min, :$checkout-timeout, :$idle-timeout, :$reaping-frequency, :$verify-timeout,
      :$verify-idle-after,
    );
  }

  method !cfg-num(%config, *@keys) {
    for @keys -> $k {
      return +%config{$k} if %config{$k}:exists && %config{$k}.defined;
    }
    Nil;
  }

  # Process-wide shared connection, keyed by connection name. Use this
  # everywhere instead of `DB.new` — creating an anonymous DB per call relies
  # on GC-driven `dispose`, which races with in-flight `allrows` iteration in
  # DBDish::Pg and produces "No such method 'PQgetisnull' for invocant of type
  # 'Any'" errors.
  method shared(Str:D :$name = default-connection() --> DB) {
    with $shared{$name} -> $db { return $db }

    # Cro serves concurrent requests on a thread pool, so the check-then-build
    # is serialized: two threads must not each build a connection for the same
    # name.
    $shared-lock.protect: {
      with $shared{$name} -> $db { return $db }

      my $db = DB.new(:$name);
      $shared = Map.new(|$shared.pairs, $name => $db);
      $db;
    }
  }

  # The connection the current context should use, resolved the one canonical
  # way: an async worker's bound connection first, then the request-scoped
  # registry (which hands out one pooled connection per request), and only
  # outside a request the process-wide shared connection. Model, Query, and
  # association proxies route through this; app-level raw SQL should too, so it
  # never drives the shared connection from many request threads at once.
  method current(Str:D :$name = default-connection() --> DB) {
    return $*AR-DB-OVERRIDE if $*AR-DB-OVERRIDE.defined;
    with $*AR-CONNECTION-REGISTRY { return .db-for($name) }
    DB.shared(name => $name);
  }

  # Test seam: swap a named shared singleton to point at a hand-built DB
  # (e.g. one wrapping a SqliteAdapter against `:memory:`). Pass `Nil` to
  # clear and force the next `.shared` to rebuild from config.
  method set-shared($db, Str:D :$name = default-connection() --> DB) {
    $shared-lock.protect: {
      $shared = Map.new(|$shared.pairs.grep({ .key ne $name }), |($db.defined ?? ($name => $db,) !! ()));
    }
    $db;
  }

  # Close this connection's primary adapter and any built pool. Never forces a
  # lazy pool into existence.
  method close(--> DB) {
    .disconnect-all with $!pool;
    $!adapter.disconnect if $!adapter.defined;
    self;
  }

  # Deterministically close every process-wide shared connection and drop the
  # registry. An END phaser calls this so the native driver handles (notably
  # libpq) are freed while the runtime is healthy. Left to the shutdown GC, the
  # finalization order is undefined and DBDish::Pg can segfault mid-teardown.
  method disconnect-shared {
    $shared-lock.protect: {
      for $shared.values -> $db {
        $db.close if $db.defined;
      }
      $shared = Map.new;
    }
  }

  END { try DB.disconnect-shared }

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
    my $adapter = self!construct-adapter(%config);
    self!apply-statement-options($adapter, %config);
    $adapter;
  }

  method !construct-adapter(%config) {
    my $cls = self.adapter-class-for(%config);
    given $cls {
      when PgAdapter {
        PgAdapter.new(
          schema   => %config<schema>   // 'public',
          host     => %config<host>     // 'localhost',
          database => %config<name>     // %config<database>,
          user     => %config<user>     // '',
          password => %config<password> // '',
          |(sslmode          => $_ with %config<sslmode>),
          |(sslrootcert      => $_ with %config<sslrootcert>),
          |(sslcert          => $_ with %config<sslcert>),
          |(sslkey           => $_ with %config<sslkey>),
          |(application-name => $_ with (%config<application_name> // %config<application-name>)),
          |(statement-timeout => .Str with (%config<statement_timeout> // %config<statement-timeout>)),
          |(lock-timeout      => .Str with (%config<lock_timeout> // %config<lock-timeout>)),
          |(idle-in-transaction-session-timeout => .Str
              with (%config<idle_in_transaction_session_timeout> // %config<idle-in-transaction-session-timeout>)),
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

  method !apply-statement-options($adapter, %config) {
    with (%config<prepared_statements> // %config<prepared-statements>) {
      $adapter.prepared-statements = self!config-bool($_);
    }

    with (%config<prepared_statement_cache_size> // %config<prepared-statement-cache-size>) {
      $adapter.prepared-statement-cache-size = .Int;
    }

    with (%config<advisory_locks> // %config<advisory-locks>) {
      $adapter.advisory-locks = self!config-bool($_);
    }

    with (%config<logging>) -> $log {
      if $log ~~ Associative {
        Log.configure(
          |(level  => .Str               with $log<level>),
          |(format => .Str               with ($log<format> // $log<formatter>)),
          |(colour => self!config-bool($_) with ($log<color> // $log<colour>)),
        );
      }
    }

    my $slow    = %config<slow_query_threshold> // %config<slow-query-threshold>;
    my $log-all = %config<log_queries>          // %config<log-queries>;

    if $slow.defined || $log-all.defined {
      LogSubscriber.attach(
        |(slow-threshold => .Num with $slow),
        log-all => ($log-all.defined && self!config-bool($log-all)),
      );
    }

    with (%config<query_log_tags> // %config<query-log-tags>) -> $tags {
      if $tags ~~ Associative {
        QueryLogs.set-tags($tags.pairs);
        QueryLogs.enable if $tags.elems;
      } elsif self!config-bool($tags) {
        QueryLogs.enable;
      }
    }
  }

  method !config-bool($value --> Bool) {
    return $value if $value ~~ Bool;
    so $value.Str.lc eq 'true' | '1' | 'yes' | 'on';
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
