use lib 'lib';
use BDD::Behave;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;

my $sqlite;
my $prior-db;

class SetupTbl is Migration {
  method change {
    self.create-table: '_cc_sqlite', [
      name => { :string, limit => 32 },
    ];
  }
}

class TryChangeColumn is Migration {
  method up {
    self.change-column: '_cc_sqlite', 'name', 'text';
  }
  method down { self.execute('SELECT 1') }
}

class TryChangeColumnDefault is Migration {
  method up {
    self.change-column-default: '_cc_sqlite', 'name', 'hello';
  }
  method down { self.execute('SELECT 1') }
}

class TryChangeColumnNull is Migration {
  method up {
    self.change-column-null: '_cc_sqlite', 'name', False;
  }
  method down { self.execute('SELECT 1') }
}

class TryColumnComment is Migration {
  method up {
    self.change-column-comment: '_cc_sqlite', 'name', 'comment';
  }
  method down { self.execute('SELECT 1') }
}

class TryTableComment is Migration {
  method up {
    self.change-table-comment: '_cc_sqlite', 'comment';
  }
  method down { self.execute('SELECT 1') }
}

my &group = $has-sqlite ?? &describe !! &xdescribe;

group "SQLite column-changes", :tag<destructive>, :order<defined>, {
  if !$has-sqlite { pending 'DBDish::SQLite not installed'; }

  before-all {
    if $has-sqlite {
      $prior-db = DB.shared;
      $sqlite   = SqliteAdapter.new(database => ':memory:');
      DB.set-shared(DB.new(adapter => $sqlite));
      SetupTbl.new.up;
    }
  }

  after-all {
    if $has-sqlite {
      DB.set-shared($prior-db // Nil);
    }
  }

  context 'change-column', {
    it 'raises a clear unsupported error', {
      expect({ TryChangeColumn.new.up }).to.raise-error;
    }
  }

  context 'change-column-default', {
    it 'raises a clear unsupported error', {
      expect({ TryChangeColumnDefault.new.up }).to.raise-error;
    }
  }

  context 'change-column-null', {
    it 'raises a clear unsupported error', {
      expect({ TryChangeColumnNull.new.up }).to.raise-error;
    }
  }

  context 'change-column-comment', {
    it 'is a silent no-op', {
      expect({ TryColumnComment.new.up }).not.to.raise-error;
    }
  }

  context 'change-table-comment', {
    it 'is a silent no-op', {
      expect({ TryTableComment.new.up }).not.to.raise-error;
    }
  }
}
