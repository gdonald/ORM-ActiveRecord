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

# Just the digits and dot of a stored numeric, so '$12.34' / '12.3400' / 12.34
# all reduce to a comparable form.
sub digits-of(Str:D $sql --> Str) {
  (scalar-of($sql) // '').Str.subst(/<-[\d.]>/, '', :g);
}

my @test-tables = < _t_num _t_tmp _t_uuid _t_bin _t_int _t_binlimit >;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateNumeric is Migration {
  method change {
    self.create-table: '_t_num', [
      big   => { :bigint },
      smol  => { :smallint },
      amt   => { :decimal, precision => 8, scale => 2 },
      rate  => { :float },
      price => { :money },
    ];
  }
}

class CreateTemporal is Migration {
  method change {
    self.create-table: '_t_tmp', [
      d  => { :date },
      tm => { :time },
      ts => { :timestamptz },
    ];
  }
}

class CreateUuid is Migration {
  method change {
    self.create-table: '_t_uuid', [ u => { :uuid } ];
  }
}

class CreateBinary is Migration {
  method change {
    self.create-table: '_t_bin', [ b => { :binary } ];
  }
}

class CreateInterval is Migration {
  method change {
    self.create-table: '_t_int', [ span => { :interval } ];
  }
}

class CreateBinaryLimit is Migration {
  method change {
    self.create-table: '_t_binlimit', [ b => { :binary, limit => 16 } ];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

my &pg-it     = $is-pg     ?? &it !! &xit;
my &mysql-it  = $is-mysql  ?? &it !! &xit;
my &sqlite-it = $is-sqlite ?? &it !! &xit;

group 'migration column types', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'numeric types', :order<defined>, {
    before-all {
      CreateNumeric.new.up;
      $adapter.exec("INSERT INTO _t_num (big, smol, amt, rate, price) VALUES (9000000000, 30000, 1234.56, 2.5, '12.34')");
    }

    it 'stores a bigint beyond 32-bit range', {
      expect((+scalar-of('SELECT big FROM _t_num')).Int).to.eq(9000000000);
    }

    it 'stores a smallint', {
      expect((+scalar-of('SELECT smol FROM _t_num')).Int).to.eq(30000);
    }

    it 'stores a decimal with precision and scale', {
      expect(((+scalar-of('SELECT amt FROM _t_num')) - 1234.56).abs < 0.01).to.be-truthy;
    }

    it 'stores a float', {
      expect(((+scalar-of('SELECT rate FROM _t_num')) - 2.5).abs < 0.001).to.be-truthy;
    }

    it 'stores a money value', {
      expect(digits-of('SELECT price FROM _t_num').contains('12.34')).to.be-truthy;
    }
  }

  context 'temporal types', :order<defined>, {
    before-all {
      CreateTemporal.new.up;
      $adapter.exec("INSERT INTO _t_tmp (d, tm, ts) VALUES ('2021-06-15', '13:14:15', '2021-06-15 13:14:15')");
    }

    it 'stores a date', {
      expect(scalar-of('SELECT d FROM _t_tmp').Str.contains('2021-06-15')).to.be-truthy;
    }

    it 'stores a time', {
      expect(scalar-of('SELECT tm FROM _t_tmp').Str.contains('13:14:15')).to.be-truthy;
    }

    it 'stores a timestamptz', {
      expect(scalar-of('SELECT ts FROM _t_tmp').Str.contains('2021-06-15')).to.be-truthy;
    }
  }

  context 'uuid type', :order<defined>, {
    before-all {
      CreateUuid.new.up;
      $adapter.exec("INSERT INTO _t_uuid (u) VALUES ('11111111-1111-1111-1111-111111111111')");
    }

    it 'round-trips a uuid value', {
      expect(scalar-of('SELECT u FROM _t_uuid').Str.contains('1111-1111')).to.be-truthy;
    }
  }

  context 'binary type', :order<defined>, {
    before-all { CreateBinary.new.up }

    pg-it 'stores raw bytes (PostgreSQL BYTEA)', {
      $adapter.exec("INSERT INTO _t_bin (b) VALUES (decode('deadbeef', 'hex'))");
      expect(scalar-of('SELECT octet_length(b) FROM _t_bin').Int).to.eq(4);
    }

    mysql-it 'stores raw bytes (MySQL BLOB)', {
      $adapter.exec("INSERT INTO _t_bin (b) VALUES (X'DEADBEEF')");
      expect(scalar-of('SELECT LENGTH(b) FROM _t_bin').Int).to.eq(4);
    }

    sqlite-it 'stores raw bytes (SQLite BLOB)', {
      $adapter.exec("INSERT INTO _t_bin (b) VALUES (X'DEADBEEF')");
      expect(scalar-of('SELECT length(b) FROM _t_bin').Int).to.eq(4);
    }
  }

  context 'binary with a limit', :order<defined>, {
    mysql-it 'becomes VARBINARY(N) on MySQL', {
      CreateBinaryLimit.new.up;
      my $ct = scalar-of("SELECT column_type FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '_t_binlimit' AND column_name = 'b'");
      expect($ct.lc.contains('varbinary')).to.be-truthy;
    }
  }

  context 'interval type', :order<defined>, {
    pg-it 'stores an interval value (PostgreSQL)', {
      CreateInterval.new.up;
      $adapter.exec("INSERT INTO _t_int (span) VALUES ('1 day')");
      expect(scalar-of('SELECT span FROM _t_int').defined).to.be-truthy;
    }

    mysql-it 'is rejected as PostgreSQL-only on MySQL', {
      expect({ CreateInterval.new.up }).to.raise-error;
    }

    sqlite-it 'is rejected as PostgreSQL-only on SQLite', {
      expect({ CreateInterval.new.up }).to.raise-error;
    }
  }
}
