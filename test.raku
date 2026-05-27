#!/usr/bin/env raku

use v6.d;
BEGIN { chdir $*PROGRAM.parent }
use lib 'lib';
use JSON::Tiny;
use DBIish;
use ORM::ActiveRecord::Support::DatabaseUrl;

$*OUT.out-buffer = False;

%*ENV<AUTHOR_TESTING> = 1;

unless %*ENV<DBIISH_MYSQL_LIB> {
  my @candidates = $*KERNEL.name eq 'darwin'
  ?? <
  /opt/homebrew/opt/mysql-client/lib/libmysqlclient.dylib
  /usr/local/opt/mysql-client/lib/libmysqlclient.dylib
  /opt/homebrew/lib/libmysqlclient.dylib
  /usr/local/lib/libmysqlclient.dylib
  >
  !! <
  /usr/lib/x86_64-linux-gnu/libmysqlclient.so
  /usr/lib64/libmysqlclient.so
  >;
  with @candidates.first(*.IO.e) -> $p {
    %*ENV<DBIISH_MYSQL_LIB> = $p;
  }
}

sub format-ts(--> Str) {
  my $d = DateTime.now;
  sprintf '%04d-%02d-%02d %02d:%02d:%02d', $d.year, $d.month, $d.day, $d.hour, $d.minute, $d.second.Int;
}

sub pg-url-from-config(--> Str) {
  return Str unless 'config/application.json'.IO.e;
  my $json = try { from-json('config/application.json'.IO.slurp) };
  return Str without $json;
  my %db = $json<db> // %();
  return Str unless ((%db<adapter> // 'pg').lc) ~~ /^ p [g | ostgres ] /;
  my $u = %db<user>;
  my $p = %db<password>;
  my $h = %db<host> // 'localhost';
  my $port = %db<port>;
  my $n = %db<name>;
  return Str without $n;
  my $auth = $u ?? ($u ~ ($p ?? ":$p" !! '') ~ '@') !! '';
  my $hp = $port ?? "$h:$port" !! $h;
  my $q  = %db<schema> ?? "?schema={%db<schema>}" !! '';
  "postgres://$auth$hp/$n$q";
}

sub try-connect(Str:D $kind, *%args --> Capture) {
  my $err;
  my $h = try {
    CATCH { default { $err = .message } }
    DBIish.connect($kind, |%args);
  };
  $h.dispose if $h.defined;
  \($h.defined, $err // '');
}

sub classify(Str:D $err --> Str) {
  return 'driver' if $err ~~ /:i 'could not find' | 'cannot load' | 'no such module' | 'cannot locate' | 'unable to find' | 'load library'/;
  return 'driver' if $err ~~ /:i 'libsqlite' | 'libpq' | 'libmysqlclient'/ && $err ~~ /:i 'cannot' | 'failed' | 'not found'/;
  return 'refused' if $err ~~ /:i 'connection refused' | 'could not connect' | 'cannot connect' | 'no route' | 'host is down' | 'timed out'/;
  return 'auth' if $err ~~ /:i 'authentication' | 'access denied' | 'password authentication failed' | 'role .* does not exist'/;
  return 'database' if $err ~~ /:i 'database .* does not exist' | 'unknown database'/;
  'other';
}

my %ADAPTERS =
  postgres => {
    dbiish          => 'Pg',
    env             => 'AR_PG_URL',
    default-url     => 'postgres://postgres@localhost:5432/ar_test',
    defaults        => { host => 'localhost', port => 5432, user => 'postgres', name => 'ar_test' },
    url-from-config => &pg-url-from-config,
    connect-args    => -> %c {
      host     => %c<host>,
      port     => %c<port>.Int,
      user     => %c<user>,
      password => %c<password> // '',
      database => %c<name>,
    },
    messages => {
      driver => -> %, $err {
        qq:to/MSG/.chomp;
        PostgreSQL driver not loadable.
          error: $err
          fix (Debian/Ubuntu):
            sudo apt-get install -y libpq-dev
            zef install --/test --force-install DBIish

          fix (macOS / Homebrew):
            brew install libpq
            export PATH="\$(brew --prefix libpq)/bin:\$PATH"
            export PKG_CONFIG_PATH="\$(brew --prefix libpq)/lib/pkgconfig:\$PKG_CONFIG_PATH"
            zef install --/test --force-install DBIish
        MSG
      },
      refused => -> %c, $err {
        my ($host, $port, $user, $name) = %c<host port user name>;
        qq:to/MSG/.chomp;
        PostgreSQL not reachable at $host:$port.
          error: $err
          fix:   docker run -d --name ar-pg -p 5432:5432 \\
                    -e POSTGRES_USER=$user -e POSTGRES_PASSWORD=postgres \\
                    -e POSTGRES_DB=$name postgres:17
                 or set AR_PG_URL='postgres://USER:PASS\@HOST:PORT/DB'
                 or edit config/application.json (db.adapter=pg)
        MSG
      },
      auth => -> %c, $err {
        my ($host, $port, $user, $name) = %c<host port user name>;
        qq:to/MSG/.chomp;
        PostgreSQL auth failed for user '$user' at $host:$port.
          error: $err
          fix:   set AR_PG_URL='postgres://USER:PASS\@$host:$port/$name'
                 or update user/password in config/application.json
        MSG
      },
      database => -> %c, $err {
        my ($host, $port, $user, $name) = %c<host port user name>;
        qq:to/MSG/.chomp;
        PostgreSQL database '$name' does not exist on $host:$port.
          error: $err
          fix:   createdb -h $host -p $port -U $user $name
                 or set AR_PG_URL to point at an existing db
        MSG
      },
      default => -> %, $err {
        qq:to/MSG/.chomp;
        PostgreSQL probe failed.
          error: $err
          fix:   set AR_PG_URL='postgres://USER:PASS\@HOST:PORT/DB'
                 or edit config/application.json
        MSG
      },
    },
  },
  mysql => {
    dbiish       => 'mysql',
    env          => 'AR_MYSQL_URL',
    default-url  => 'mysql://root@127.0.0.1:3306/ar_test',
    defaults     => { host => '127.0.0.1', port => 3306, user => 'root', name => 'ar_test' },
    connect-args => -> %c {
      host     => %c<host>,
      port     => %c<port>.Int,
      user     => %c<user>,
      password => %c<password> // '',
      database => %c<name>,
    },
    messages => {
      driver => -> %, $err {
        qq:to/MSG/.chomp;
        MySQL driver not loadable.
          error: $err
          cause: DBDish::mysql searches libmysqlclient versions 16..21 only,
                 but recent installs ship version 24+. It does NOT consult
                 pkg-config or mysql_config — only the DBIISH_MYSQL_LIB env
                 var (or the standard dynamic-loader search path).

          fix (macOS / Homebrew):
            brew install mysql-client
            export DBIISH_MYSQL_LIB=\$(brew --prefix mysql-client)/lib/libmysqlclient.dylib

          fix (Debian/Ubuntu):
            sudo apt-get install -y libmysqlclient21
            export DBIISH_MYSQL_LIB=/usr/lib/x86_64-linux-gnu/libmysqlclient.so

          Then re-run ./test.raku — it auto-detects DBIISH_MYSQL_LIB on next
          invocation if mysql-client is in a standard Homebrew or apt path.
        MSG
      },
      refused => -> %c, $err {
        my ($host, $port, $name) = %c<host port name>;
        qq:to/MSG/.chomp;
        MySQL not reachable at $host:$port.
          error: $err
          fix:   docker run -d --name ar-mysql -p 3306:3306 \\
                    -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=$name mysql:8.4
                 or set AR_MYSQL_URL='mysql://USER:PASS\@HOST:PORT/DB'
        MSG
      },
      auth => -> %c, $err {
        my ($host, $port, $user, $name) = %c<host port user name>;
        qq:to/MSG/.chomp;
        MySQL auth failed for user '$user' at $host:$port.
          error: $err
          fix:   set AR_MYSQL_URL='mysql://USER:PASS\@$host:$port/$name'
        MSG
      },
      database => -> %c, $err {
        my ($host, $port, $user, $name) = %c<host port user name>;
        qq:to/MSG/.chomp;
        MySQL database '$name' does not exist on $host:$port.
          error: $err
          fix:   mysql -h $host -P $port -u $user -p -e 'CREATE DATABASE $name'
                 or set AR_MYSQL_URL to point at an existing db
        MSG
      },
      default => -> %, $err {
        qq:to/MSG/.chomp;
        MySQL probe failed.
          error: $err
          fix:   set AR_MYSQL_URL='mysql://USER:PASS\@HOST:PORT/DB'
        MSG
      },
    },
  },
  sqlite => {
    dbiish       => 'SQLite',
    env          => 'AR_SQLITE_URL',
    default-url  => 'sqlite:db/test.sqlite3',
    defaults     => {},
    connect-args => -> % { database => ':memory:' },
    messages => {
      driver => -> %, $err {
        qq:to/MSG/.chomp;
        SQLite driver not loadable.
          error: $err
          fix (Debian/Ubuntu):
            sudo apt-get install -y libsqlite3-dev
            zef install --/test --force-install DBIish

          fix (macOS): libsqlite3 is preinstalled; just rebuild:
            zef install --/test --force-install DBIish
        MSG
      },
      default => -> %, $err {
        qq:to/MSG/.chomp;
        SQLite probe failed.
          error: $err
          fix:   ensure libsqlite3 is on the system; reinstall with
                 `zef install --/test --force-install DBIish`
        MSG
      },
    },
  };

sub skip-message(Str:D $name, %c, Str:D $err --> Str) {
  my %a = %ADAPTERS{$name};
  my $cls = classify($err);
  my $tpl = %a<messages>{$cls} // %a<messages><default>;
  $tpl.(%c, $err);
}

sub probe(Str:D $name, Str:D $url --> Capture) {
  return \(False, "unknown adapter $name", "unknown adapter $name") unless %ADAPTERS{$name}:exists;
  my %a = %ADAPTERS{$name};
  my %c = parse-database-url($url);
  for %a<defaults>.kv -> $k, $v { %c{$k} //= $v }
  my %args = %a<connect-args>.(%c);
  my ($ok, $err) = try-connect(%a<dbiish>, |%args).list;
  \($ok, $err, $ok ?? '' !! skip-message($name, %c, $err));
}

sub run-once(Str:D :$name, Str:D :$url --> Int) {
  say '';
  say "==> [{format-ts()}] adapter=$name";
  %*ENV<DATABASE_URL> = $url;

  my $migrate = run :env(%*ENV, DISABLE-SQL-LOG => 'True'),
                    'raku', '-Ilib', 'bin/ar';
  return $migrate.exitcode unless $migrate.exitcode == 0;

  my $prove = run 'prove6', '-Ilib', 't';
  return $prove.exitcode unless $prove.exitcode == 0;

  # behave runs every spec file in its own process (one EVAL'd compunit per
  # invocation), matching prove6's per-test isolation model.
  my @specs = find-spec-files('specs'.IO).map(*.absolute).sort;

  my $any-behave-fail = 0;
  for @specs -> $f {
    my $proc = run 'behave', $f;
    $any-behave-fail = $proc.exitcode if $proc.exitcode != 0;
  }

  # Some specs leave DB.shared in non-canonical state (e.g. reset-spec wipes
  # all tables; round-trip-spec re-migrates a swapped sqlite). Restore the
  # canonical schema so the next test.raku run starts clean.
  run :env(%*ENV, DISABLE-SQL-LOG => 'True'),
      'raku', '-Ilib', 'bin/ar';

  $any-behave-fail;
}

sub find-spec-files(IO::Path $dir) {
  my @out;
  for $dir.dir -> $entry {
    next if $entry.basename.starts-with('.');
    if $entry.d {
      @out.append: find-spec-files($entry);
    } elsif $entry.basename ~~ /spec '.' raku $/ {
      @out.push: $entry;
    }
  }
  @out;
}

sub parse-adapter-args(--> List) {
  my %alias = pg => 'postgres', postgres => 'postgres', postgresql => 'postgres',
  mysql => 'mysql',
  sqlite => 'sqlite', sqlite3 => 'sqlite';
  my @args = @*ARGS;
  if @args.grep({ $_ eq '-h' || $_ eq '--help' }) {
    say q:to/USAGE/;
    Usage: ./test.raku [--adapter=NAME[,NAME...]]
      NAME: pg|postgres|mysql|sqlite (default: all configured)
    USAGE
    exit 0;
  }
  my @picked;
  my $i = 0;
  while $i < @args.elems {
    my $a = @args[$i];
    if $a ~~ /^ '--adapter=' (.+) $/ {
      @picked.append: ~$0;
    } elsif $a eq '--adapter' {
      die "--adapter requires a value" unless $i + 1 < @args.elems;
      @picked.append: @args[++$i];
    } else {
      die "unknown arg: $a (use --adapter=pg|mysql|sqlite)";
    }
    $i++;
  }
  @picked.map(*.split(',', :skip-empty)).flat.map({
      %alias{.lc} // die "unknown adapter: $_ (use pg|mysql|sqlite)"
  }).list;
}

my @wanted = parse-adapter-args();

my @runs;
my Bool $skip-probe = False;

if my $external = %*ENV<DATABASE_URL> {
  my $kind = parse-database-url($external)<adapter>;
  my $name = $kind eq 'pg' ?? 'postgres' !! $kind;
  @runs.push: { :$name, :url($external) };
  $skip-probe = True;
} else {
  for <postgres mysql sqlite> -> $name {
    my %a = %ADAPTERS{$name};
    my $config-url = %a<url-from-config>:exists ?? %a<url-from-config>.() !! Str;
    my $url = %*ENV{%a<env>} // $config-url // %a<default-url>;
    @runs.push: { :$name, :$url };
  }
}

if @wanted {
  my %want = @wanted.map: * => True;
  @runs = @runs.grep({ %want{ .<name> } }).list;
  die "no adapters matched --adapter filter ({@wanted.join(',')})" unless @runs;
}

my @skipped;
my $any-fail = False;
my %durations;
my $total-start = now;

END {
  if %durations {
    say '';
    say '==> Runtimes';
    for @runs -> %r {
      next unless %durations{%r<name>}:exists;
      printf "  %-9s %7.2fs\n", %r<name>, %durations{%r<name>};
    }
    printf "  %-9s %7.2fs\n", 'total', (now - $total-start).Num;
  }
  if @skipped {
    say '';
    say '==> Skipped';
    for @skipped -> $s {
      say "  - $s<name>";
      say $s<msg>.indent(6);
    }
  }
}

for @runs -> %r {
  my $name = %r<name>;
  my $url  = %r<url>;

  unless $skip-probe {
    my ($ok, $err, $msg) = probe($name, $url).list;
    unless $ok {
      say '';
      say "==> [{format-ts()}] SKIP $name";
      say $msg.indent(2);
      @skipped.push: { :$name, :$msg };
      next;
    }
  }

  my $start = now;
  my $rc = run-once(:$name, :$url);
  %durations{$name} = (now - $start).Num;
  $any-fail = True if $rc != 0;
}

exit $any-fail ?? 1 !! 0;
