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

my @test-tables = < _ft_tsv _ft_tsq _ft_bit _ft_vbit _ft_ci _ft_enum >;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
  try { $adapter.ddl-drop-enum('mood', :if-exists) }
}

class CreateTsvector is Migration {
  method change { self.create-table: '_ft_tsv', [ v => { :tsvector } ]; }
}

class CreateTsquery is Migration {
  method change { self.create-table: '_ft_tsq', [ q => { :tsquery } ]; }
}

class CreateBit is Migration {
  method change { self.create-table: '_ft_bit', [ b => { :bit, limit => 3 } ]; }
}

class CreateBitVarying is Migration {
  method change { self.create-table: '_ft_vbit', [ b => { :bit_varying, limit => 8 } ]; }
}

class CreateCitext is Migration {
  method change {
    self.enable-extension('citext');
    self.create-table: '_ft_ci', [ t => { :citext } ];
  }
}

class CreateMoodEnum is Migration {
  method change { self.create-enum('mood', <happy sad>); }
}

class CreateEnumCol is Migration {
  method change { self.create-table: '_ft_enum', [ m => { enum_type => 'mood' } ]; }
}

my &group = $has-db ?? &describe !! &xdescribe;

my &pg-it     = $is-pg     ?? &it !! &xit;
my &mysql-it  = $is-mysql  ?? &it !! &xit;
my &sqlite-it = $is-sqlite ?? &it !! &xit;

group 'migration full-text and misc column types', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'tsvector (10.8.1)', :order<defined>, {
    pg-it 'round-trips a tsvector (PostgreSQL)', {
      CreateTsvector.new.up;
      $adapter.exec(q{INSERT INTO _ft_tsv (v) VALUES ('cat:1 dog:2')});
      expect(scalar-of('SELECT v FROM _ft_tsv').Str.contains('cat')).to.be-truthy;
    }

    mysql-it 'is PostgreSQL-only on MySQL', {
      expect({ CreateTsvector.new.up }).to.raise-error;
    }

    sqlite-it 'is PostgreSQL-only on SQLite', {
      expect({ CreateTsvector.new.up }).to.raise-error;
    }
  }

  context 'tsquery (10.8.1)', :order<defined>, {
    pg-it 'round-trips a tsquery (PostgreSQL)', {
      CreateTsquery.new.up;
      $adapter.exec(q{INSERT INTO _ft_tsq (q) VALUES ('cat & dog')});
      expect(scalar-of('SELECT q FROM _ft_tsq').Str.contains('cat')).to.be-truthy;
    }

    mysql-it 'is PostgreSQL-only on MySQL', {
      expect({ CreateTsquery.new.up }).to.raise-error;
    }

    sqlite-it 'is PostgreSQL-only on SQLite', {
      expect({ CreateTsquery.new.up }).to.raise-error;
    }
  }

  context 'bit (10.8.2)', :order<defined>, {
    pg-it 'round-trips a BIT(n) value (PostgreSQL)', {
      CreateBit.new.up;
      $adapter.exec(q{INSERT INTO _ft_bit (b) VALUES (B'101')});
      expect(scalar-of('SELECT b FROM _ft_bit').Str.contains('101')).to.be-truthy;
    }

    mysql-it 'round-trips a BIT(n) value (MySQL)', {
      CreateBit.new.up;
      $adapter.exec(q{INSERT INTO _ft_bit (b) VALUES (b'101')});
      expect(scalar-of('SELECT BIN(b) FROM _ft_bit').Str.contains('101')).to.be-truthy;
    }

    sqlite-it 'is unsupported on SQLite', {
      expect({ CreateBit.new.up }).to.raise-error;
    }
  }

  context 'bit varying (10.8.2)', :order<defined>, {
    pg-it 'round-trips a BIT VARYING value (PostgreSQL)', {
      CreateBitVarying.new.up;
      $adapter.exec(q{INSERT INTO _ft_vbit (b) VALUES (B'1010')});
      expect(scalar-of('SELECT b FROM _ft_vbit').Str.contains('1010')).to.be-truthy;
    }

    mysql-it 'is PostgreSQL-only on MySQL', {
      expect({ CreateBitVarying.new.up }).to.raise-error;
    }

    sqlite-it 'is PostgreSQL-only on SQLite', {
      expect({ CreateBitVarying.new.up }).to.raise-error;
    }
  }

  context 'citext (10.8.3)', :order<defined>, {
    pg-it 'matches case-insensitively (PostgreSQL)', {
      CreateCitext.new.up;
      $adapter.exec(q{INSERT INTO _ft_ci (t) VALUES ('Hello')});
      expect(scalar-of(q{SELECT COUNT(*) FROM _ft_ci WHERE t = 'hello'}).Int).to.eq(1);
    }

    mysql-it 'is PostgreSQL-only on MySQL', {
      expect({ CreateCitext.new.up }).to.raise-error;
    }

    sqlite-it 'is PostgreSQL-only on SQLite', {
      expect({ CreateCitext.new.up }).to.raise-error;
    }
  }

  context 'user-defined enum type (10.8.4)', :order<defined>, {
    pg-it 'uses an existing enum type as a column type (PostgreSQL)', {
      CreateMoodEnum.new.up;
      CreateEnumCol.new.up;
      $adapter.exec(q{INSERT INTO _ft_enum (m) VALUES ('happy')});
      expect(scalar-of('SELECT m FROM _ft_enum').Str).to.eq('happy');
    }

    mysql-it 'is PostgreSQL-only on MySQL', {
      expect({ CreateEnumCol.new.up }).to.raise-error;
    }

    sqlite-it 'is PostgreSQL-only on SQLite', {
      expect({ CreateEnumCol.new.up }).to.raise-error;
    }
  }
}
