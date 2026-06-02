use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;

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

my $kind  = adapter-kind();
my $is-pg = $kind eq 'pg';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($table) {
  $adapter.get-fields(table => $table).map({ $_[0] }).list;
}

# Primary-key column names, in key order, for the active adapter.
sub primary-key-columns($table) {
  my $rows = do given $kind {
    when 'pg' {
      $adapter.exec(qq:to/SQL/);
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = '$table'::regclass AND i.indisprimary
        ORDER BY array_position(i.indkey, a.attnum)
        SQL
    }
    when 'mysql' {
      $adapter.exec(qq:to/SQL/);
        SELECT COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = '$table'
          AND CONSTRAINT_NAME = 'PRIMARY'
        ORDER BY ORDINAL_POSITION
        SQL
    }
    when 'sqlite' {
      $adapter.exec("PRAGMA table_info($table)")
        .grep({ $_[5].Int > 0 })
        .sort({ $^a[5].Int <=> $^b[5].Int })
        .map({ [$_[1]] });
    }
    default { [] }
  };
  $rows.map({ $_[0].Str }).list;
}

# Declared SQL type of one column (lower-cased), for the active adapter.
sub column-type($table, $col) {
  given $kind {
    when 'pg' | 'mysql' {
      my $rows = $adapter.exec(qq:to/SQL/);
        SELECT data_type FROM information_schema.columns
        WHERE table_name = '$table' AND column_name = '$col'
        SQL
      $rows.elems ?? $rows[0][0].Str.lc !! '';
    }
    when 'sqlite' {
      my $row = $adapter.exec("PRAGMA table_info($table)").first({ $_[1] eq $col });
      $row ?? $row[2].Str.lc !! '';
    }
    default { '' }
  }
}

my @test-tables = <
  _pk_default _pk_none _pk_uuid _pk_custom _pk_named _pk_composite
>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class PkCreateDefault is Migration {
  method change {
    self.create-table: '_pk_default', [ name => { :string, limit => 16 } ];
  }
}

class PkCreateNone is Migration {
  method change {
    self.create-table: '_pk_none', [ name => { :string, limit => 16 } ],
      id => False, primary-key => False;
  }
}

class PkCreateUuid is Migration {
  method change {
    self.create-table: '_pk_uuid', [ name => { :string, limit => 16 } ],
      id => 'uuid';
  }
}

class PkCreateCustom is Migration {
  method change {
    self.create-table: '_pk_custom', [ name => { :string, limit => 16 } ],
      id => 'bigint';
  }
}

class PkCreateNamed is Migration {
  method change {
    self.create-table: '_pk_named', [ name => { :string, limit => 16 } ],
      primary-key => 'guid';
  }
}

class PkCreateComposite is Migration {
  method change {
    self.create-table: '_pk_composite', [
      shop_id => { :integer },
      id      => { :integer },
      name    => { :string, limit => 16 },
    ], id => False, primary-key => ['shop_id', 'id'];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration primary keys', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all { if $has-db { cleanup-tables } }
  after-all  { if $has-db { cleanup-tables } }

  context 'default surrogate id', :order<defined>, {
    before-all { if $has-db { PkCreateDefault.new.up } }
    after-all  { if $has-db { PkCreateDefault.new.down } }

    it 'adds an id column', {
      expect('id' (elem) column-names('_pk_default')).to.be-truthy;
    }

    it 'makes id the primary key', {
      expect(primary-key-columns('_pk_default').join(',')).to.eq('id');
    }
  }

  context 'id => False, primary-key => False', :order<defined>, {
    before-all { if $has-db { PkCreateNone.new.up } }
    after-all  { if $has-db { PkCreateNone.new.down } }

    it 'creates no id column', {
      expect('id' (elem) column-names('_pk_none')).to.be-falsy;
    }

    it 'creates no primary key', {
      expect(primary-key-columns('_pk_none').elems).to.eq(0);
    }
  }

  context 'id => uuid', :order<defined>, {
    before-all { if $has-db { PkCreateUuid.new.up } }
    after-all  { if $has-db { PkCreateUuid.new.down } }

    it 'keeps id as the primary key', {
      expect(primary-key-columns('_pk_uuid').join(',')).to.eq('id');
    }

    my &pg-it = $is-pg ?? &it !! &xit;
    pg-it 'gives id the uuid type (PostgreSQL)', {
      expect(column-type('_pk_uuid', 'id')).to.eq('uuid');
    }
  }

  context 'custom primary key type', :order<defined>, {
    before-all { if $has-db { PkCreateCustom.new.up } }
    after-all  { if $has-db { PkCreateCustom.new.down } }

    it 'keeps id as the primary key', {
      expect(primary-key-columns('_pk_custom').join(',')).to.eq('id');
    }
  }

  context 'renamed primary key', :order<defined>, {
    before-all { if $has-db { PkCreateNamed.new.up } }
    after-all  { if $has-db { PkCreateNamed.new.down } }

    it 'names the surrogate column guid', {
      expect('guid' (elem) column-names('_pk_named')).to.be-truthy;
    }

    it 'makes guid the primary key', {
      expect(primary-key-columns('_pk_named').join(',')).to.eq('guid');
    }

    it 'creates no id column', {
      expect('id' (elem) column-names('_pk_named')).to.be-falsy;
    }
  }

  context 'composite primary key', :order<defined>, {
    before-all { if $has-db { PkCreateComposite.new.up } }
    after-all  { if $has-db { PkCreateComposite.new.down } }

    it 'makes both columns the primary key in order', {
      expect(primary-key-columns('_pk_composite').join(',')).to.eq('shop_id,id');
    }

    it 'auto-inverts to drop the table on down', {
      PkCreateComposite.new.down;
      expect(table-exists('_pk_composite')).to.be-falsy;
      PkCreateComposite.new.up;
    }
  }
}
