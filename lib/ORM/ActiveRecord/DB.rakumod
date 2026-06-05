
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::Connection::Pool;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Support::Environment;

class DB is export {
  my %shared;
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

    ConnectionPool.new(
      builder => { self.build-connection },
      :$size, :$min, :$checkout-timeout, :$idle-timeout, :$reaping-frequency, :$verify-timeout,
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
