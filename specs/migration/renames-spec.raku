use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($name) {
  $adapter.get-fields(table => $name).map({ $_[0] }).list;
}

sub index-exists($name) {
  my $rows = do given $adapter.^name {
    when /Pg/      { $adapter.exec("SELECT 1 FROM pg_indexes WHERE indexname = '$name'") }
    when /MySql/   { $adapter.exec("SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() AND index_name = '$name'") }
    when /Sqlite/  { $adapter.exec("SELECT 1 FROM sqlite_master WHERE type='index' AND name='$name'") }
  };
  ?$rows.elems;
}

my @test-tables = <_rn_old _rn_new _rn_cols _rn_idx>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateRnOld is Migration {
  method change {
    self.create-table: '_rn_old', [
      name => { :string, limit => 32 },
    ];
  }
}

class DoRenameTable is Migration {
  method change {
    self.rename-table: '_rn_old', '_rn_new';
  }
}

class CreateRnCols is Migration {
  method change {
    self.create-table: '_rn_cols', [
      handle => { :string, limit => 32 },
    ];
  }
}

class DoRenameCol is Migration {
  method change {
    self.rename-column: '_rn_cols', 'handle', 'username';
  }
}

class CreateRnIdx is Migration {
  method change {
    self.create-table: '_rn_idx', [
      label => { :string, limit => 32 },
    ];
    self.add-index: '_rn_idx', :label;
  }
}

class DoRenameIdx is Migration {
  method change {
    self.rename-index: '_rn_idx', '_rn_idx_label_idx', '_rn_idx_label_new_idx';
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration renames', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  context 'rename-table', :order<defined>, {
    before-all { if $has-db { cleanup-tables; CreateRnOld.new.up } }
    after-all  { if $has-db { cleanup-tables } }

    context 'before up', {
      it 'creates the source table', {
        expect(table-exists('_rn_old')).to.be-truthy;
      }
    }

    context 'after up', :order<defined>, {
      before-all { if $has-db { DoRenameTable.new.up } }

      it 'moves the source to the new name', {
        expect(table-exists('_rn_new')).to.be-truthy;
      }

      it 'removes the old name', {
        expect(table-exists('_rn_old')).to.be-falsy;
      }
    }

    context 'after down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { DoRenameTable.new.down } }

      it 'restores the old name', {
        expect(table-exists('_rn_old')).to.be-truthy;
      }

      it 'removes the new name', {
        expect(table-exists('_rn_new')).to.be-falsy;
      }
    }
  }

  context 'rename-column', :order<defined>, {
    before-all { if $has-db { cleanup-tables; CreateRnCols.new.up } }
    after-all  { if $has-db { cleanup-tables } }

    context 'before up', {
      it 'adds the source column', {
        expect('handle' (elem) column-names('_rn_cols')).to.be-truthy;
      }
    }

    context 'after up', :order<defined>, {
      before-all { if $has-db { DoRenameCol.new.up } }

      it 'adds the new column name', {
        expect('username' (elem) column-names('_rn_cols')).to.be-truthy;
      }

      it 'removes the old column name', {
        expect('handle' (elem) column-names('_rn_cols')).to.be-falsy;
      }
    }

    context 'after down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { DoRenameCol.new.down } }

      it 'restores the old column name', {
        expect('handle' (elem) column-names('_rn_cols')).to.be-truthy;
      }

      it 'removes the new column name', {
        expect('username' (elem) column-names('_rn_cols')).to.be-falsy;
      }
    }
  }

  context 'rename-index', :order<defined>, {
    before-all { if $has-db { cleanup-tables; CreateRnIdx.new.up } }
    after-all  { if $has-db { cleanup-tables } }

    context 'before up', {
      it 'creates the source index', {
        expect(index-exists('_rn_idx_label_idx')).to.be-truthy;
      }
    }

    context 'after up', :order<defined>, {
      before-all { if $has-db { DoRenameIdx.new.up } }

      it 'creates the new index name', {
        expect(index-exists('_rn_idx_label_new_idx')).to.be-truthy;
      }

      it 'removes the old index name', {
        expect(index-exists('_rn_idx_label_idx')).to.be-falsy;
      }
    }

    context 'after down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { DoRenameIdx.new.down } }

      it 'restores the old index name', {
        expect(index-exists('_rn_idx_label_idx')).to.be-truthy;
      }

      it 'removes the new index name', {
        expect(index-exists('_rn_idx_label_new_idx')).to.be-falsy;
      }
    }
  }
}
