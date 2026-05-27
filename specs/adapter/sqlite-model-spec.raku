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
use ORM::ActiveRecord::Model;

class SmmWidget is Model {
  method table-name { 'smm_widgets' }

  submethod BUILD {
    self.validate: 'name', { :presence }
  }
}

my &group = $has-sqlite ?? &describe !! &xdescribe;

group "SqliteAdapter-backed Model", :tag<destructive>, {
  my $saved-shared;
  my $sqlite;

  before-all {
    $saved-shared = DB.shared;
    $sqlite       = SqliteAdapter.new(database => ':memory:');
    DB.set-shared(DB.new(adapter => $sqlite));

    $sqlite.ddl-create-table('smm_widgets', [
      name   => { :string, limit => 64 },
      qty    => { :integer, default => 0 },
      active => { :boolean, default => True },
    ]);
    $sqlite.ddl-add-timestamps('smm_widgets');
  }

  after-all {
    DB.set-shared($saved-shared);
  }

  before-each { SmmWidget.destroy-all }
  after-each  { SmmWidget.destroy-all }

  context 'create + find', {
    it 'returns a surrogate id from RETURNING or last_insert_rowid', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.id).to.be-truthy;
    }

    it 'persists the name', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.name).to.eq('Alpha');
    }

    it 'persists the qty', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.qty).to.eq(3);
    }

    it 'persists active as True', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.active).to.eq(True);
    }

    it 'round-trips the name via find', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = SmmWidget.find($w.id);
      expect($found.name).to.eq('Alpha');
    }

    it 'reads active back as Bool through the PRAGMA-driven schema', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = SmmWidget.find($w.id);
      expect($found.active).to.be-a(Bool);
    }

    it 'preserves active = True on read', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = SmmWidget.find($w.id);
      expect($found.active).to.eq(True);
    }

    it 'reads created_at back as DateTime', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = SmmWidget.find($w.id);
      expect($found.created_at).to.be-a(DateTime);
    }
  }

  context 'update with Bool = False', {
    it 'preserves the False after update (no longer mangled)', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      my $reloaded = SmmWidget.find($w.id);
      expect($reloaded.active).to.eq(False);
    }

    it 'updates qty', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      my $reloaded = SmmWidget.find($w.id);
      expect($reloaded.qty).to.eq(9);
    }
  }

  context 'where / count / find-by (Alpha updated to False before Beta/Gamma)', {
    before-each {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      SmmWidget.create({ name => 'Beta',  qty => 1, active => False });
      SmmWidget.create({ name => 'Gamma', qty => 5, active => True });
    }

    it 'counts three rows after three inserts', {
      expect(SmmWidget.count).to.eq(3);
    }

    it 'narrows where(active => True) to one row', {
      expect(SmmWidget.where({ active => True }).count).to.eq(1);
    }

    it 'narrows where(active => False) to two rows', {
      expect(SmmWidget.where({ active => False }).count).to.eq(2);
    }

    it 'hits the right row via find-by', {
      my $by-name = SmmWidget.find-by({ name => 'Gamma' });
      expect($by-name.qty).to.eq(5);
    }
  }

  context 'destroy', {
    it 'removes exactly one row via destroy', {
      my $w = SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      SmmWidget.create({ name => 'Beta',  qty => 1, active => False });
      SmmWidget.create({ name => 'Gamma', qty => 5, active => True });

      my $by-name = SmmWidget.find-by({ name => 'Gamma' });
      $by-name.destroy;

      expect(SmmWidget.count).to.eq(2);
    }

    it 'clears the table via destroy-all', {
      SmmWidget.create({ name => 'Alpha', qty => 3, active => True });
      SmmWidget.create({ name => 'Beta',  qty => 1, active => False });

      SmmWidget.destroy-all;

      expect(SmmWidget.count).to.eq(0);
    }
  }
}
