use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter      = DB.shared.adapter;
my $has-db       = $adapter.defined && $adapter.is-connected;
my $current      = $has-db ?? live-adapter-name($adapter) !! Str;
my $is-sqlite    = $current.defined && $current eq 'sqlite';
my $skip-reason  = !$has-db
  ?? 'no database connection available'
  !! ($is-sqlite ?? 'SQLite has no ALTER COLUMN; change-column* requires table rebuild' !! Str);
my $active       = $has-db && !$is-sqlite;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-types($table) {
  my %h;
  for $adapter.get-fields(table => $table) -> $row {
    %h{$row[0]} = $row[1];
  }
  %h;
}

sub column-default(Str:D $table, Str:D $name) {
  my $sql = qq:to/SQL/;
    SELECT column_default
      FROM information_schema.columns
     WHERE table_name = '$table' AND column_name = '$name'
    SQL
  my @rows = $adapter.exec($sql);
  return Nil unless @rows.elems;

  my $raw = @rows[0][0];
  return Nil without $raw;
  $raw ~~ Blob ?? $raw.decode('utf-8') !! $raw.Str;
}

my @test-tables = <_cc_basic _cc_default _cc_null _cc_comment _cc_rev_null _cc_rev_default _cc_rev_comment _cc_table_comment _cc_irreversible>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateBasic is Migration {
  method change {
    self.create-table: '_cc_basic', [
      name => { :string, limit => 32 },
    ];
  }
}

class WidenBasicName is Migration {
  method up {
    self.change-column: '_cc_basic', 'name', 'text';
  }
  method down {
    self.change-column: '_cc_basic', 'name', 'string', limit => 32;
  }
}

class CreateDefault is Migration {
  method change {
    self.create-table: '_cc_default', [
      status => { :string, limit => 32 },
    ];
  }
}

class SetDefault is Migration {
  method up {
    self.change-column-default: '_cc_default', 'status', 'pending';
  }
  method down {
    self.change-column-default: '_cc_default', 'status', Nil;
  }
}

class CreateNull is Migration {
  method change {
    self.create-table: '_cc_null', [
      email => { :string, limit => 64 },
    ];
  }
}

class TightenNull is Migration {
  method change {
    self.change-column-null: '_cc_null', 'email', False;
  }
}

class CreateRevNull is Migration {
  method change {
    self.create-table: '_cc_rev_null', [
      label => { :string, limit => 32 },
    ];
  }
}

class BackfillThenTighten is Migration {
  method change {
    self.change-column-null: '_cc_rev_null', 'label', False, 'unknown';
  }
}

class CreateCommentTbl is Migration {
  method change {
    self.create-table: '_cc_comment', [
      note => { :string, limit => 32 },
    ];
  }
}

class AddNoteComment is Migration {
  method up {
    self.change-column-comment: '_cc_comment', 'note', 'free-form text';
  }
  method down {
    self.change-column-comment: '_cc_comment', 'note', Nil;
  }
}

class CreateTableCommentTbl is Migration {
  method change {
    self.create-table: '_cc_table_comment', [
      n => { :integer },
    ];
  }
}

class AddTblComment is Migration {
  method up {
    self.change-table-comment: '_cc_table_comment', 'sample table';
  }
  method down {
    self.change-table-comment: '_cc_table_comment', Nil;
  }
}

class CreateRevDefault is Migration {
  method change {
    self.create-table: '_cc_rev_default', [
      status => { :string, limit => 32 },
    ];
  }
}

class SwapDefault is Migration {
  method change {
    self.change-column-default: '_cc_rev_default', 'status',
      from => 'pending', to => 'active';
  }
}

class CreateRevComment is Migration {
  method change {
    self.create-table: '_cc_rev_comment', [
      n => { :integer },
    ];
  }
}

class SwapComment is Migration {
  method change {
    self.change-column-comment: '_cc_rev_comment', 'n',
      from => 'old', to => 'new';
    self.change-table-comment: '_cc_rev_comment',
      from => 'old tbl', to => 'new tbl';
  }
}

class IrreversibleChangeCol is Migration {
  method change {
    self.create-table: '_cc_irreversible', [name => { :string, limit => 32 }];
    self.change-column: '_cc_irreversible', 'name', 'text';
  }
}

class IrreversibleDefault is Migration {
  method change {
    self.change-column-default: '_cc_default', 'status', 'frozen';
  }
}

my &group = $active ?? &describe !! &xdescribe;

group 'migration column changes', :order<defined>, {
  if !$active { pending $skip-reason // 'not applicable'; }

  before-all { if $active { cleanup-tables } }
  after-all  { if $active { cleanup-tables } }

  context 'change-column updates column type', :order<defined>, {
    before-all {
      if $active {
        CreateBasic.new.up;
        WidenBasicName.new.up;
      }
    }

    it 'changes the column type to text', {
      my %types = column-types('_cc_basic');
      my $name-type = (%types<name> // '').lc;
      expect($name-type.contains('text')).to.be-truthy;
    }
  }

  context 'change-column-default', :order<defined>, {
    before-all { if $active { CreateDefault.new.up } }

    context 'after setting a default', :order<defined>, {
      before-all { if $active { SetDefault.new.up } }

      it 'applies the new default', {
        my $default-after-set = column-default('_cc_default', 'status');
        expect(($default-after-set // '').contains('pending')).to.be-truthy;
      }
    }

    context 'after dropping the default with Nil', :order<defined>, {
      before-all { if $active { SetDefault.new.down } }

      it 'drops the default', {
        my $default-after-drop = column-default('_cc_default', 'status');
        expect($default-after-drop.defined).to.be-falsy;
      }
    }
  }

  context 'change-column-null toggles NOT NULL', :order<defined>, {
    before-all {
      if $active {
        CreateNull.new.up;
        TightenNull.new.up;
      }
    }

    it 'enforces NOT NULL after change-column-null(_, _, False)', {
      expect({ $adapter.exec("INSERT INTO _cc_null (email) VALUES (NULL)") }).to.raise-error;
    }

    context 'after auto-inverted down', :order<defined>, {
      before-all { if $active { TightenNull.new.down } }

      it 'restores nullability', {
        expect({ $adapter.exec("INSERT INTO _cc_null (email) VALUES (NULL)") }).not.to.raise-error;
      }
    }
  }

  context 'change-column-null with backfill default', :order<defined>, {
    before-all {
      if $active {
        CreateRevNull.new.up;
        $adapter.exec("INSERT INTO _cc_rev_null (label) VALUES (NULL)");
        BackfillThenTighten.new.up;
      }
    }

    it 'fills existing NULL rows with the backfill default', {
      my @rev-rows = $adapter.exec('SELECT label FROM _cc_rev_null');
      expect(@rev-rows[0][0]).to.eq('unknown');
    }
  }

  context 'change-column-comment', :order<defined>, {
    before-all { if $active { CreateCommentTbl.new.up } }

    it 'runs without error', {
      expect({ AddNoteComment.new.up }).not.to.raise-error;
    }
  }

  context 'change-table-comment', :order<defined>, {
    before-all { if $active { CreateTableCommentTbl.new.up } }

    it 'runs without error', {
      expect({ AddTblComment.new.up }).not.to.raise-error;
    }
  }

  context 'change-column-default with from/to is reversible', :order<defined>, {
    before-all {
      if $active {
        CreateRevDefault.new.up;
        $adapter.ddl-change-column-default('_cc_rev_default', 'status', 'pending');
      }
    }

    context 'on up', :order<defined>, {
      before-all { if $active { SwapDefault.new.up } }

      it 'applies the to default', {
        my $after-up = column-default('_cc_rev_default', 'status') // '';
        expect($after-up.contains('active')).to.be-truthy;
      }
    }

    context 'on down (auto-inverts back to from)', :order<defined>, {
      before-all { if $active { SwapDefault.new.down } }

      it 'restores the from default', {
        my $after-down = column-default('_cc_rev_default', 'status') // '';
        expect($after-down.contains('pending')).to.be-truthy;
      }
    }
  }

  context 'change-column-comment / change-table-comment with from/to', :order<defined>, {
    before-all { if $active { CreateRevComment.new.up } }

    it 'runs forward', {
      expect({ SwapComment.new.up }).not.to.raise-error;
    }

    it 'auto-inverts on down', {
      expect({ SwapComment.new.down }).not.to.raise-error;
    }
  }

  context 'change-column inside change is irreversible', :order<defined>, {
    before-all { if $active { IrreversibleChangeCol.new.up } }

    it 'throws X::IrreversibleMigration on down', {
      expect({ IrreversibleChangeCol.new.down }).to.raise-error(X::IrreversibleMigration);
    }
  }

  context 'change-column-default without from/to is irreversible', {
    it 'throws X::IrreversibleMigration on down', {
      expect({ IrreversibleDefault.new.down }).to.raise-error(X::IrreversibleMigration);
    }
  }
}
