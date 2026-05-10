
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;

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

  method !build-adapter(%config) {
    my $kind = (%config<adapter> // 'pg').lc;
    given $kind {
      when 'pg' | 'postgres' | 'postgresql' {
        PgAdapter.new(
          schema   => %config<schema>,
          host     => %config<host>,
          database => %config<name>,
          user     => %config<user>,
          password => %config<password>,
        );
      }
      when 'sqlite' | 'sqlite3' {
        SqliteAdapter.new(
          database => %config<name> // %config<database> // ':memory:',
        );
      }
      default { die "DB: unsupported adapter '$kind'" }
    }
  }

  method read-config {
    my %config;
    if (my $fh = open 'config/application.json', :r) {
      my $contents = $fh.slurp-rest;
      $fh.close;
      my $json = from-json($contents);
      for $json<db>.kv -> $k, $v { %config{$k} = $v }
    }
    %config;
  }
}
