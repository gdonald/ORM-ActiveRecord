
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;

class DB is export {
  my DB $shared;

  has Adapter $.adapter handles *;

  submethod BUILD {
    my %config = self.read-config;
    $!adapter = self!build-adapter(%config);
  }

  # Process-wide shared connection. Use this everywhere instead of `DB.new` —
  # creating an anonymous DB per call relies on GC-driven `dispose`, which
  # races with in-flight `allrows` iteration in DBDish::Pg and produces
  # "No such method 'PQgetisnull' for invocant of type 'Any'" errors.
  method shared(--> DB) {
    $shared //= DB.new;
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
