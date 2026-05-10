
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::Support::DatabaseUrl;

class DB is export {
  my DB $shared;

  has Adapter $.adapter handles *;

  submethod BUILD(Adapter :$adapter) {
    if $adapter.defined {
      $!adapter = $adapter;
    } else {
      my %config = self.read-config;
      $!adapter = self!build-adapter(%config);
    }
  }

  # Process-wide shared connection. Use this everywhere instead of `DB.new` —
  # creating an anonymous DB per call relies on GC-driven `dispose`, which
  # races with in-flight `allrows` iteration in DBDish::Pg and produces
  # "No such method 'PQgetisnull' for invocant of type 'Any'" errors.
  method shared(--> DB) {
    $shared //= DB.new;
    $shared;
  }

  # Test seam: swap the shared singleton to point at a hand-built DB
  # (e.g. one wrapping a SqliteAdapter against `:memory:`). Pass `Nil` to
  # clear and force the next `.shared` to rebuild from config.
  method set-shared($db --> DB) {
    $shared = $db;
    $shared;
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

  method read-config(Str :$path = 'config/application.json') {
    if my $url = %*ENV<DATABASE_URL> {
      return parse-database-url($url);
    }
    my %config;
    if (my $fh = open $path, :r) {
      my $contents = $fh.slurp-rest;
      $fh.close;
      my $json = from-json($contents);
      for $json<db>.kv -> $k, $v { %config{$k} = $v }
    }
    %config;
  }
}
