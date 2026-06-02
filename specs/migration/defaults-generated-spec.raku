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

# SQL expression that yields the current time, per adapter. Used to prove a
# function default emits raw SQL rather than a quoted string literal.
sub now-fn(--> Str) {
  given $kind {
    when 'pg'     { 'now()' }
    when 'mysql'  { 'CURRENT_TIMESTAMP(6)' }
    default       { 'CURRENT_TIMESTAMP' }
  }
}

# Per-adapter column spec for the collation column.
sub coll-spec {
  given $kind {
    when 'pg'    { { :string, limit => 32, collation => 'C' } }
    when 'mysql' { { :string, limit => 32, charset => 'utf8mb4', collation => 'utf8mb4_bin' } }
    default      { { :text, collation => 'NOCASE' } }
  }
}

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

my @test-tables = <
  _dg_fn _dg_lit _dg_gen _dg_virt _dg_coll _dg_cmt
>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateFn is Migration {
  method change {
    self.create-table: '_dg_fn', [
      n       => { :integer },
      made_at => { :timestamp, default => -> { now-fn() } },
    ];
  }
}

class CreateLit is Migration {
  method change {
    self.create-table: '_dg_lit', [
      n      => { :integer },
      status => { :string, limit => 32, default => 'pending' },
    ];
  }
}

class CreateGen is Migration {
  method change {
    self.create-table: '_dg_gen', [
      a       => { :integer },
      doubled => { :integer, as => 'a * 2', stored => True },
    ];
  }
}

class CreateVirt is Migration {
  method change {
    self.create-table: '_dg_virt', [
      a       => { :integer },
      tripled => { :integer, as => 'a * 3' },
    ];
  }
}

class CreateColl is Migration {
  method change {
    self.create-table: '_dg_coll', [ name => coll-spec() ];
  }
}

class CreateCmt is Migration {
  method change {
    self.create-table: '_dg_cmt', [
      note => { :string, limit => 32, comment => 'free text' },
    ], comment => 'sample table';
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

# Per-adapter example selectors: the active adapter runs the example, the
# others mark it pending — no `if` inside the blocks.
my &pg-it     = $is-pg     ?? &it !! &xit;
my &mysql-it  = $is-mysql  ?? &it !! &xit;
my &sqlite-it = $is-sqlite ?? &it !! &xit;

group 'migration defaults and generated columns', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'function default', :order<defined>, {
    before-all {
      CreateFn.new.up;
      $adapter.exec('INSERT INTO _dg_fn (n) VALUES (1)');
    }

    it 'populates the column from the function on insert', {
      expect(scalar-of('SELECT made_at FROM _dg_fn').defined).to.be-truthy;
    }
  }

  context 'literal default', :order<defined>, {
    before-all {
      CreateLit.new.up;
      $adapter.exec('INSERT INTO _dg_lit (n) VALUES (1)');
    }

    it 'stores the literal default value', {
      expect(scalar-of('SELECT status FROM _dg_lit')).to.eq('pending');
    }
  }

  context 'stored generated column', :order<defined>, {
    before-all {
      CreateGen.new.up;
      $adapter.exec('INSERT INTO _dg_gen (a) VALUES (21)');
    }

    it 'computes the generated value from the expression', {
      expect(scalar-of('SELECT doubled FROM _dg_gen').Int).to.eq(42);
    }
  }

  context 'virtual generated column', :order<defined>, {
    before-all {
      CreateVirt.new.up;
      $adapter.exec('INSERT INTO _dg_virt (a) VALUES (10)');
    }

    it 'computes the value on read', {
      expect(scalar-of('SELECT tripled FROM _dg_virt').Int).to.eq(30);
    }
  }

  context 'column collation', :order<defined>, {
    before-all {
      CreateColl.new.up;
      $adapter.exec("INSERT INTO _dg_coll (name) VALUES ('Hello')");
    }

    pg-it 'records the requested collation on PostgreSQL', {
      my $c = scalar-of(qq{SELECT collation_name FROM information_schema.columns WHERE table_name = '_dg_coll' AND column_name = 'name'});
      expect($c).to.eq('C');
    }

    mysql-it 'records the requested collation on MySQL', {
      my $c = scalar-of(qq{SELECT collation_name FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '_dg_coll' AND column_name = 'name'});
      expect($c).to.eq('utf8mb4_bin');
    }

    sqlite-it 'matches case-insensitively on SQLite', {
      expect(scalar-of("SELECT COUNT(*) FROM _dg_coll WHERE name = 'hello'").Int).to.eq(1);
    }
  }

  context 'create-time comments', :order<defined>, {
    before-all { CreateCmt.new.up }

    pg-it 'sets the column comment on PostgreSQL', {
      my $c = scalar-of(qq:to/SQL/);
        SELECT d.description
          FROM pg_description d
          JOIN pg_class c ON c.oid = d.objoid
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.objsubid
         WHERE c.relname = '_dg_cmt' AND a.attname = 'note'
        SQL
      expect($c).to.eq('free text');
    }

    pg-it 'sets the table comment on PostgreSQL', {
      expect(scalar-of(q{SELECT obj_description('_dg_cmt'::regclass)})).to.eq('sample table');
    }

    mysql-it 'sets the column comment on MySQL', {
      my $c = scalar-of(qq{SELECT column_comment FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '_dg_cmt' AND column_name = 'note'});
      expect($c).to.eq('free text');
    }

    mysql-it 'sets the table comment on MySQL', {
      my $c = scalar-of(qq{SELECT table_comment FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '_dg_cmt'});
      expect($c).to.eq('sample table');
    }

    sqlite-it 'ignores comments and still creates the table on SQLite', {
      expect(table-exists('_dg_cmt')).to.be-truthy;
    }
  }
}
