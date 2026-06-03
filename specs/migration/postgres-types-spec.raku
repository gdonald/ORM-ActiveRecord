use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub adapter-kind(--> Str) {
  return 'none' without $adapter;
  given $adapter.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

my $kind      = adapter-kind();
my $is-pg     = $kind eq 'pg';
my $is-mysql  = $kind eq 'mysql';
my $is-sqlite = $kind eq 'sqlite';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub scalar-of(Str:D $sql) {
  my @rows = $adapter.exec($sql);
  return Nil unless @rows.elems;
  my $v = @rows[0][0];
  return Nil without $v;
  $v ~~ Blob ?? $v.decode('utf-8') !! $v;
}

my @test-tables = < _tc_arr _tc_rng _tc_ltree _tc_net _tc_geo >;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateArrays is Migration {
  method change {
    self.create-table: '_tc_arr', [
      tags  => { :integer, array => True },
      names => { :string, array => True },
    ];
  }
}

class CreateRanges is Migration {
  method change {
    self.create-table: '_tc_rng', [
      r4    => { :int4range },
      r8    => { :int8range },
      rn    => { :numrange },
      rts   => { :tsrange },
      rtstz => { :tstzrange },
      rd    => { :daterange },
    ];
  }
}

class CreateLtree is Migration {
  method change {
    self.enable-extension('ltree');
    self.create-table: '_tc_ltree', [ p => { :ltree } ];
  }
}

class CreateNetwork is Migration {
  method change {
    self.create-table: '_tc_net', [
      addr => { :inet },
      net  => { :cidr },
      mac  => { :macaddr },
    ];
  }
}

class CreateGeo is Migration {
  method change {
    self.create-table: '_tc_geo', [
      pt => { :point },
      ln => { :line },
      sg => { :lseg },
      bx => { :box },
      pa => { :path },
      pl => { :polygon },
      ci => { :circle },
    ];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

my &pg-it     = $is-pg     ?? &it !! &xit;
my &mysql-it  = $is-mysql  ?? &it !! &xit;
my &sqlite-it = $is-sqlite ?? &it !! &xit;

group 'migration PostgreSQL-specific column types', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'arrays (10.5.1)', :order<defined>, {
    pg-it 'round-trips an integer[] column (PostgreSQL)', {
      CreateArrays.new.up;
      $adapter.exec(q{INSERT INTO _tc_arr (tags, names) VALUES ('{1,2,3}', '{a,b}')});
      expect(scalar-of('SELECT tags FROM _tc_arr').Str.contains('1')).to.be-truthy;
    }

    mysql-it 'array is PostgreSQL-only on MySQL', {
      expect({ CreateArrays.new.up }).to.raise-error;
    }

    sqlite-it 'array is PostgreSQL-only on SQLite', {
      expect({ CreateArrays.new.up }).to.raise-error;
    }
  }

  context 'range types (10.5.2)', :order<defined>, {
    pg-it 'creates all six range types and round-trips one (PostgreSQL)', {
      CreateRanges.new.up;
      $adapter.exec(q{INSERT INTO _tc_rng (r4, r8, rn, rts, rtstz, rd) VALUES ('[1,5)', '[1,100)', '[1.5,2.5)', '[2021-01-01 00:00,2021-01-02 00:00)', '[2021-01-01 00:00+00,2021-01-02 00:00+00)', '[2021-01-01,2021-02-01)')});
      expect(scalar-of('SELECT r4 FROM _tc_rng').Str.contains('1')).to.be-truthy;
    }

    mysql-it 'range types are PostgreSQL-only on MySQL', {
      expect({ CreateRanges.new.up }).to.raise-error;
    }

    sqlite-it 'range types are PostgreSQL-only on SQLite', {
      expect({ CreateRanges.new.up }).to.raise-error;
    }
  }

  context 'ltree (10.5.3)', :order<defined>, {
    pg-it 'round-trips an ltree path (PostgreSQL)', {
      CreateLtree.new.up;
      $adapter.exec(q{INSERT INTO _tc_ltree (p) VALUES ('a.b.c')});
      expect(scalar-of('SELECT p FROM _tc_ltree').Str.contains('a')).to.be-truthy;
    }

    mysql-it 'ltree is PostgreSQL-only on MySQL', {
      expect({ CreateLtree.new.up }).to.raise-error;
    }

    sqlite-it 'ltree is PostgreSQL-only on SQLite', {
      expect({ CreateLtree.new.up }).to.raise-error;
    }
  }

  context 'network types (10.6)', :order<defined>, {
    pg-it 'round-trips inet / cidr / macaddr (PostgreSQL)', {
      CreateNetwork.new.up;
      $adapter.exec(q{INSERT INTO _tc_net (addr, net, mac) VALUES ('192.168.0.1', '192.168.0.0/24', '08:00:2b:01:02:03')});
      expect(scalar-of('SELECT addr FROM _tc_net').Str.contains('192.168')).to.be-truthy;
    }

    mysql-it 'network types are PostgreSQL-only on MySQL', {
      expect({ CreateNetwork.new.up }).to.raise-error;
    }

    sqlite-it 'network types are PostgreSQL-only on SQLite', {
      expect({ CreateNetwork.new.up }).to.raise-error;
    }
  }

  context 'geometric types (10.7)', :order<defined>, {
    pg-it 'creates all geometric types and round-trips a point (PostgreSQL)', {
      CreateGeo.new.up;
      $adapter.exec(q{INSERT INTO _tc_geo (pt, ln, sg, bx, pa, pl, ci) VALUES ('(1,2)', '{1,2,3}', '[(0,0),(1,1)]', '((0,0),(1,1))', '((0,0),(1,1),(2,2))', '((0,0),(1,1),(2,0))', '<(0,0),1>')});
      expect(scalar-of('SELECT pt FROM _tc_geo').Str.contains('1')).to.be-truthy;
    }

    mysql-it 'geometric types are PostgreSQL-only on MySQL', {
      expect({ CreateGeo.new.up }).to.raise-error;
    }

    sqlite-it 'geometric types are PostgreSQL-only on SQLite', {
      expect({ CreateGeo.new.up }).to.raise-error;
    }
  }
}
