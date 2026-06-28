use DBIish;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migrate;
use ORM::ActiveRecord::Schema::DbReady;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Support::Environment;

unit module ORM::ActiveRecord::Schema::WorkerDbs;

# `active-record --create-db` and `active-record --migrate` live here. Both consult
# config/application.json for the active environment and act on every
# configured connection's database — all of them for a multi-db setup, or just
# the one otherwise. With :parallel they instead target the N per-worker copies
# (`_0` .. `_{N-1}`) that `behave --parallel N` uses. Creation and migration
# are separate steps. Connection failures are reported and skipped (no
# fail-fast).

sub sqlite-name(%cfg --> Str) { %cfg<name> // %cfg<database> // ':memory:' }
sub db-name(%cfg --> Str)     { %cfg<name> // %cfg<database> // '' }

sub ensure-sqlite(%cfg --> Bool) {
  my $path = sqlite-name(%cfg);
  return True if $path eq ':memory:';

  my $io = $path.IO;
  $io.parent.mkdir unless $io.parent.e;
  $io.spurt('') unless $io.e;
  True;
}

sub ensure-pg(%cfg --> Bool) {
  my $name = db-name(%cfg);
  return False unless $name;

  my $h = DBIish.connect('Pg',
    host     => %cfg<host>     // 'localhost',
    port     => (%cfg<port>    // 5432).Int,
    user     => %cfg<user>     // '',
    password => %cfg<password> // '',
    database => 'postgres',
  );
  LEAVE { $h.dispose if $h.defined }

  my $exists = $h.execute('SELECT 1 FROM pg_database WHERE datname = ?', $name).row;
  $h.do("CREATE DATABASE \"$name\"") unless $exists;
  True;
}

sub ensure-mysql(%cfg --> Bool) {
  my $name = db-name(%cfg);
  return False unless $name;

  my $h = DBIish.connect('mysql',
    host     => %cfg<host>     // '127.0.0.1',
    port     => (%cfg<port>    // 3306).Int,
    user     => %cfg<user>     // 'root',
    password => %cfg<password> // '',
  );
  LEAVE { $h.dispose if $h.defined }

  $h.do("CREATE DATABASE IF NOT EXISTS `$name`");
  True;
}

sub ensure-database(%cfg --> Bool) {
  my $adapter = (%cfg<adapter> // 'pg').lc;
  given $adapter {
    when 'sqlite' | 'sqlite3'             { ensure-sqlite(%cfg) }
    when 'pg' | 'postgres' | 'postgresql' { ensure-pg(%cfg) }
    when 'mysql' | 'mysql2' | 'mariadb'   { ensure-mysql(%cfg) }
    default { die "create-db: unsupported adapter '$adapter'" }
  }
}

sub drop-sqlite(%cfg --> Bool) {
  my $path = sqlite-name(%cfg);
  return True if $path eq ':memory:';
  $path.IO.unlink if $path.IO.e;
  True;
}

sub drop-pg(%cfg --> Bool) {
  my $name = db-name(%cfg);
  return False unless $name;

  my $h = DBIish.connect('Pg',
    host     => %cfg<host>     // 'localhost',
    port     => (%cfg<port>    // 5432).Int,
    user     => %cfg<user>     // '',
    password => %cfg<password> // '',
    database => 'postgres',
  );
  LEAVE { $h.dispose if $h.defined }

  $h.do("DROP DATABASE IF EXISTS \"$name\"");
  True;
}

sub drop-mysql(%cfg --> Bool) {
  my $name = db-name(%cfg);
  return False unless $name;

  my $h = DBIish.connect('mysql',
    host     => %cfg<host>     // '127.0.0.1',
    port     => (%cfg<port>    // 3306).Int,
    user     => %cfg<user>     // 'root',
    password => %cfg<password> // '',
  );
  LEAVE { $h.dispose if $h.defined }

  $h.do("DROP DATABASE IF EXISTS `$name`");
  True;
}

sub drop-database(%cfg --> Bool) {
  my $adapter = (%cfg<adapter> // 'pg').lc;
  given $adapter {
    when 'sqlite' | 'sqlite3'             { drop-sqlite(%cfg) }
    when 'pg' | 'postgres' | 'postgresql' { drop-pg(%cfg) }
    when 'mysql' | 'mysql2' | 'mariadb'   { drop-mysql(%cfg) }
    default { die "drop-db: unsupported adapter '$adapter'" }
  }
}

# Create one connection's database for worker index $i (or the base database
# when $i is undefined).
sub create-one(Str $conn, %base, Int $i --> Bool) {
  my %cfg = $i.defined ?? apply-worker-suffix(%base, $i) !! %base;

  my $ok = try { ensure-database(%cfg) };
  unless $ok {
    my $err = $!.defined ?? $!.message !! 'database could not be created';
    note "create-db: skipping $conn worker {$i // 'base'} ({db-name(%cfg) || sqlite-name(%cfg)}): $err";
    return False;
  }

  True;
}

# Drop one connection's database for worker index $i (or the base database when
# $i is undefined). The inverse of create-one.
sub drop-one(Str $conn, %base, Int $i --> Bool) {
  my %cfg = $i.defined ?? apply-worker-suffix(%base, $i) !! %base;

  DB.set-shared(Nil, name => $conn);

  my $ok = try { drop-database(%cfg) };
  unless $ok {
    my $err = $!.defined ?? $!.message !! 'database could not be dropped';
    note "drop-db: skipping $conn worker {$i // 'base'} ({db-name(%cfg) || sqlite-name(%cfg)}): $err";
    return False;
  }

  True;
}

# Migrate one connection's database for worker index $i. The worker overlay env
# makes DB.read-config resolve the suffixed name; a fresh DB.shared per call
# rebinds the connection.
sub migrate-one(Str $conn, %base, Int $i, Int $count --> Bool) {
  my %cfg = $i.defined ?? apply-worker-suffix(%base, $i) !! %base;
  return True if sqlite-name(%cfg) eq ':memory:';

  temp %*ENV;
  if $i.defined {
    %*ENV<BEHAVE_WORKER_INDEX> = $i.Str;
    %*ENV<BEHAVE_WORKER_COUNT> = $count.Str;
  } else {
    %*ENV<BEHAVE_WORKER_INDEX>:delete;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;
  }
  %*ENV<DISABLE-SQL-LOG> = 'True';

  DB.set-shared(Nil, name => $conn);
  Migrate.new(connection => $conn).run;
  DB.set-shared(Nil, name => $conn);

  True;
}

# Drop every table in one connection's database for worker index $i (or the
# base database when $i is undefined), so a following migrate rebuilds from a
# clean slate. Always non-interactive and quiet — this is a test-env operation.
sub reset-one(Str $conn, %base, Int $i, Int $count --> Bool) {
  my %cfg = $i.defined ?? apply-worker-suffix(%base, $i) !! %base;
  return True if sqlite-name(%cfg) eq ':memory:';

  temp %*ENV;
  if $i.defined {
    %*ENV<BEHAVE_WORKER_INDEX> = $i.Str;
    %*ENV<BEHAVE_WORKER_COUNT> = $count.Str;
  } else {
    %*ENV<BEHAVE_WORKER_INDEX>:delete;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;
  }
  %*ENV<DISABLE-SQL-LOG> = 'True';

  DB.set-shared(Nil, name => $conn);
  Migrate.new(connection => $conn).reset(args => ['--yes', '--quiet']);
  DB.set-shared(Nil, name => $conn);

  True;
}

sub each-target(&body, Bool :$parallel, Str :$path, Str :$env, Int :$count) {
  # Clear any inherited worker overlay so base configs read cleanly.
  temp %*ENV;
  %*ENV<BEHAVE_WORKER_INDEX>:delete;
  %*ENV<BEHAVE_WORKER_COUNT>:delete;

  # The parallel worker count is the explicit override when given, else the
  # env's `parallel` key from config.
  my $n       = $parallel ?? ($count // DB.env-parallel(:$path, :$env)) !! 1;
  my @indices = $parallel ?? (^$n).list !! (Int,);

  for DB.connection-names(:$path, :$env) -> $conn {
    my %base = DB.read-config(:$path, name => $conn, :$env);
    next unless %base.elems;

    body($conn, %base, $_, $n) for @indices;
  }
}

sub create-test-databases(Bool :$parallel = False,
                          Int  :$count,
                          Str  :$path = 'config/application.json',
                          Str  :$env  = $parallel ?? 'test' !! current-env('development')) is export {
  each-target(-> $conn, %base, $i, $n { create-one($conn, %base, $i) },
              :$parallel, :$path, :$env, :$count);
}

sub migrate-test-databases(Bool :$parallel = False,
                           Int  :$count,
                           Str  :$path = 'config/application.json',
                           Str  :$env  = $parallel ?? 'test' !! current-env('development')) is export {
  each-target(-> $conn, %base, $i, $n { migrate-one($conn, %base, $i, $n) },
              :$parallel, :$path, :$env, :$count);
}

sub drop-test-databases(Bool :$parallel = False,
                        Int  :$count,
                        Str  :$path = 'config/application.json',
                        Str  :$env  = $parallel ?? 'test' !! current-env('development')) is export {
  each-target(-> $conn, %base, $i, $n { drop-one($conn, %base, $i) },
              :$parallel, :$path, :$env, :$count);
}

sub reset-test-databases(Bool :$parallel = False,
                         Int  :$count,
                         Str  :$path = 'config/application.json',
                         Str  :$env  = $parallel ?? 'test' !! current-env('development')) is export {
  each-target(-> $conn, %base, $i, $n { reset-one($conn, %base, $i, $n) },
              :$parallel, :$path, :$env, :$count);
}

# Pre-flight readiness for every expected database (each configured connection,
# times the worker count when :parallel). Returns one problem line per database
# that is missing or has unrun migrations; an empty list means all are ready.
sub check-test-databases(Bool :$parallel = False,
                         Int  :$count,
                         Str  :$path = 'config/application.json',
                         Str  :$env  = $parallel ?? 'test' !! current-env('development') --> List) is export {
  my @problems;

  each-target(-> $conn, %base, $i, $n {
    my %cfg   = $i.defined ?? apply-worker-suffix(%base, $i) !! %base;
    my $label = db-name(%cfg) || sqlite-name(%cfg);

    given database-status(%cfg) {
      when 'missing' { @problems.push: "missing database: $label" }
      when 'pending' { @problems.push: "unrun migrations: $label" }
    }
  }, :$parallel, :$path, :$env, :$count);

  @problems.List;
}
