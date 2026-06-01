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

my $kind      = adapter-kind();
my $is-pg     = $kind eq 'pg';
my $is-sqlite = $kind eq 'sqlite';
my $is-mysql  = $kind eq 'mysql';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($table) {
  $adapter.get-fields(table => $table).map({ $_[0] }).list;
}

sub index-exists($name) {
  my $rows = do given $kind {
    when 'pg'     { $adapter.exec("SELECT 1 FROM pg_indexes WHERE indexname = '$name'") }
    when 'mysql'  { $adapter.exec("SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() AND index_name = '$name'") }
    when 'sqlite' { $adapter.exec("SELECT 1 FROM sqlite_master WHERE type='index' AND name='$name'") }
    default       { [] }
  };
  ?$rows.elems;
}

my @test-tables = <
  _jt_posts__jt_users _jt_custom _jt_posts _jt_users
  _tbl_main _tbl_force _tbl_fc _tbl_temporary _tbl_ine
>;

sub cleanup-tables {
  $adapter.exec('DROP VIEW IF EXISTS _tbl_fc_view') if $is-pg;
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateMain is Migration {
  method change {
    self.create-table: '_tbl_main', [
      name  => { :string, limit => 32 },
      label => { :string, limit => 32 },
    ];
  }
}

# create-join-table / drop-join-table
class CreateJoin is Migration {
  method change {
    self.create-join-table: '_jt_posts', '_jt_users';
  }
}

class CreateJoinNamed is Migration {
  method change {
    self.create-join-table: '_jt_posts', '_jt_users', table-name => '_jt_custom';
  }
}

# change-table with a coalesced bulk ALTER
class BulkAddColumns is Migration {
  method change {
    self.change-table: '_tbl_main', -> $t {
      $t.add-column: :age => { :integer };
      $t.add-column: :city => { :string, limit => 32 };
      $t.add-index: :age;
    }, bulk => True;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration tables', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all { if $has-db { cleanup-tables; CreateMain.new.up } }
  after-all  { if $has-db { cleanup-tables } }

  context 'create-join-table', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { CreateJoin.new.up } }
      after-all  { if $has-db { CreateJoin.new.down } }

      it 'creates the sorted <a>_<b> join table', {
        expect(table-exists('_jt_posts__jt_users')).to.be-truthy;
      }

      it 'adds the first foreign-key column', {
        expect('_jt_post_id' (elem) column-names('_jt_posts__jt_users')).to.be-truthy;
      }

      it 'adds the second foreign-key column', {
        expect('_jt_user_id' (elem) column-names('_jt_posts__jt_users')).to.be-truthy;
      }

      it 'creates no id primary-key column', {
        expect('id' (elem) column-names('_jt_posts__jt_users')).to.be-falsy;
      }
    }

    context 'after down (auto-inverts to drop-join-table)', :order<defined>, {
      before-all { if $has-db { CreateJoin.new.up; CreateJoin.new.down } }

      it 'drops the join table', {
        expect(table-exists('_jt_posts__jt_users')).to.be-falsy;
      }
    }

    context 'with an explicit table-name', :order<defined>, {
      before-all { if $has-db { CreateJoinNamed.new.up } }
      after-all  { if $has-db { CreateJoinNamed.new.down } }

      it 'uses the override name', {
        expect(table-exists('_jt_custom')).to.be-truthy;
      }
    }
  }

  context 'change-table with bulk', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { BulkAddColumns.new.up } }

      it 'adds the first column in the coalesced ALTER', {
        expect('age' (elem) column-names('_tbl_main')).to.be-truthy;
      }

      it 'adds the second column in the coalesced ALTER', {
        expect('city' (elem) column-names('_tbl_main')).to.be-truthy;
      }

      it 'runs the index op alongside the column changes', {
        expect(index-exists('_tbl_main_age_idx')).to.be-truthy;
      }
    }

    context 'after down (auto-inverts each op)', :order<defined>, {
      before-all { if $has-db { BulkAddColumns.new.down } }

      it 'removes the first column', {
        expect('age' (elem) column-names('_tbl_main')).to.be-falsy;
      }

      it 'removes the second column', {
        expect('city' (elem) column-names('_tbl_main')).to.be-falsy;
      }
    }
  }

  context 'force on create-table', :order<defined>, {
    my class CreateForce is Migration {
      method change {
        self.create-table: '_tbl_force', [ old_col => { :string, limit => 16 } ];
      }
    }

    my class RecreateForce is Migration {
      method up {
        self.create-table: '_tbl_force', [ new_col => { :string, limit => 16 } ],
          force => True;
      }
      method down { self.drop-table: '_tbl_force' }
    }

    before-all {
      if $has-db { CreateForce.new.up; RecreateForce.new.up }
    }
    after-all { if $has-db { try { $adapter.ddl-drop-table('_tbl_force') } } }

    it 'drops and recreates the table with the new shape', {
      expect('new_col' (elem) column-names('_tbl_force')).to.be-truthy;
    }

    it 'leaves no trace of the old shape', {
      expect('old_col' (elem) column-names('_tbl_force')).to.be-falsy;
    }
  }

  context 'temporary tables', :order<defined>, {
    my class CreateTemp is Migration {
      method change {
        self.create-table: '_tbl_temporary', [ note => { :string, limit => 16 } ],
          temporary => True;
      }
    }

    before-all { if $has-db { CreateTemp.new.up } }
    after-all  { if $has-db { try { $adapter.ddl-drop-table('_tbl_temporary') } } }

    it 'creates a usable temporary table on the session', {
      $adapter.exec("INSERT INTO _tbl_temporary (note) VALUES ('x')");
      expect($adapter.exec('SELECT COUNT(*) FROM _tbl_temporary')[0][0].Int).to.eq(1);
    }
  }

  context 'if-exists / if-not-exists on table ops', :order<defined>, {
    my class CreateIne is Migration {
      method change {
        self.create-table: '_tbl_ine', [ name => { :string, limit => 16 } ];
      }
    }

    my class CreateIneAgain is Migration {
      method up {
        self.create-table: '_tbl_ine', [ name => { :string, limit => 16 } ],
          if-not-exists => True;
      }
      method down { }
    }

    before-all { if $has-db { CreateIne.new.up } }
    after-all  { if $has-db { try { $adapter.ddl-drop-table('_tbl_ine') } } }

    it 'create-table if-not-exists is a no-op when the table exists', {
      expect({ CreateIneAgain.new.up }).not.to.raise-error;
    }

    it 'drop-table if-exists is a no-op when the table is absent', {
      expect({ $adapter.ddl-drop-table('_tbl_absent', :if-exists) }).not.to.raise-error;
    }
  }

  # CREATE / DROP INDEX IF [NOT] EXISTS: PostgreSQL and SQLite.
  my &idx-group = ($is-pg || $is-sqlite) ?? &context !! &xcontext;

  idx-group 'if-not-exists / if-exists on index ops', :order<defined>, {
    if !($is-pg || $is-sqlite) { pending 'index IF [NOT] EXISTS is PostgreSQL / SQLite only'; }

    my class AddIdxIne is Migration {
      method up {
        self.add-index: '_tbl_main', :label, if-not-exists => True;
        self.add-index: '_tbl_main', :label, if-not-exists => True;
      }
      method down {
        self.remove-index: '_tbl_main', :label, if-exists => True;
        self.remove-index: '_tbl_main', :label, if-exists => True;
      }
    }

    it 'add-index if-not-exists tolerates a repeat', {
      expect({ AddIdxIne.new.up }).not.to.raise-error;
    }

    it 'creates the index', {
      expect(index-exists('_tbl_main_label_idx')).to.be-truthy;
    }

    it 'remove-index if-exists tolerates a missing index', {
      expect({ AddIdxIne.new.down }).not.to.raise-error;
    }
  }

  # Column-level IF [NOT] EXISTS: PostgreSQL only.
  my &col-group = $is-pg ?? &context !! &xcontext;

  col-group 'if-not-exists / if-exists on column ops (PostgreSQL)', :order<defined>, {
    if !$is-pg { pending 'column IF [NOT] EXISTS is PostgreSQL only'; }

    my class AddColIne is Migration {
      method up {
        self.add-column: '_tbl_main', :nickname => { :string, limit => 16 },
          if-not-exists => True;
        self.add-column: '_tbl_main', :nickname => { :string, limit => 16 },
          if-not-exists => True;
      }
      method down {
        self.remove-column: '_tbl_main', :nickname, if-exists => True;
        self.remove-column: '_tbl_main', :nickname, if-exists => True;
      }
    }

    it 'add-column if-not-exists tolerates a repeat', {
      expect({ AddColIne.new.up }).not.to.raise-error;
    }

    it 'adds the column', {
      expect('nickname' (elem) column-names('_tbl_main')).to.be-truthy;
    }

    it 'remove-column if-exists tolerates a missing column', {
      expect({ AddColIne.new.down }).not.to.raise-error;
    }
  }

  # PostgreSQL force => 'cascade' drops dependents the plain drop cannot.
  my &cascade-group = $is-pg ?? &context !! &xcontext;

  cascade-group 'force cascade (PostgreSQL)', :order<defined>, {
    if !$is-pg { pending 'force cascade differs only on PostgreSQL'; }

    my class CreateFc is Migration {
      method change {
        self.create-table: '_tbl_fc', [ name => { :string, limit => 16 } ];
      }
    }

    my class RecreateFcCascade is Migration {
      method up {
        self.create-table: '_tbl_fc', [ name => { :string, limit => 16 } ],
          force => 'cascade';
      }
      method down { self.drop-table: '_tbl_fc', :cascade }
    }

    before-all {
      if $is-pg {
        CreateFc.new.up;
        $adapter.exec('CREATE VIEW _tbl_fc_view AS SELECT id FROM _tbl_fc');
      }
    }
    after-all {
      if $is-pg {
        $adapter.exec('DROP VIEW IF EXISTS _tbl_fc_view');
        try { $adapter.ddl-drop-table('_tbl_fc') };
      }
    }

    it 'recreates the table even with a dependent view', {
      RecreateFcCascade.new.up;
      expect(table-exists('_tbl_fc')).to.be-truthy;
    }
  }

  # Unsupported gated clauses raise rather than emit broken SQL.
  my &mysql-group = $is-mysql ?? &context !! &xcontext;

  mysql-group 'MySQL rejects unsupported IF [NOT] EXISTS clauses', :order<defined>, {
    if !$is-mysql { pending 'MySQL-only guard checks'; }

    my class AddIdxIneMysql is Migration {
      method change {
        self.add-index: '_tbl_main', :label, if-not-exists => True;
      }
    }

    my class AddColIneMysql is Migration {
      method change {
        self.add-column: '_tbl_main', :nickname => { :string, limit => 16 },
          if-not-exists => True;
      }
    }

    it 'raises for add-index if-not-exists', {
      expect({ AddIdxIneMysql.new.up }).to.raise-error;
    }

    it 'raises for add-column if-not-exists', {
      expect({ AddColIneMysql.new.up }).to.raise-error;
    }
  }

  my &sqlite-group = $is-sqlite ?? &context !! &xcontext;

  sqlite-group 'SQLite rejects unsupported column IF [NOT] EXISTS', :order<defined>, {
    if !$is-sqlite { pending 'SQLite-only guard checks'; }

    my class AddColIneSqlite is Migration {
      method change {
        self.add-column: '_tbl_main', :nickname => { :string, limit => 16 },
          if-not-exists => True;
      }
    }

    it 'raises for add-column if-not-exists', {
      expect({ AddColIneSqlite.new.up }).to.raise-error;
    }
  }
}
