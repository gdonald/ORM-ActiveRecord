use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS bk_widgets');
  $adapter.ddl-create-table('bk_widgets', [
    name   => { :string, limit => 64 },
    qty    => { :integer, default => 0 },
    active => { :boolean, default => False },
  ]);
  $adapter.ddl-add-timestamps('bk_widgets');
  $adapter.exec('CREATE UNIQUE INDEX bk_widgets_name_idx ON bk_widgets (name)');
}

class BkWidget is Model {
  method table-name { 'bk_widgets' }

  submethod BUILD { }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS bk_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'bulk write operations', {
  before-each {
    BkWidget.destroy-all if $has-db;
  }

  context 'update-all on a where-scoped relation', {
    my $n;

    before-each {
      BkWidget.create({ name => 'a', qty => 1 });
      BkWidget.create({ name => 'b', qty => 2 });
      BkWidget.create({ name => 'c', qty => 3 });

      $n = BkWidget.where({ qty => 1..2 }).update-all(active => True);
    }

    it 'returns the row count', {
      expect($n).to.eq(2);
    }

    it 'applies to matching rows', {
      expect(BkWidget.where({ name => 'a' }).first.active).to.eq(True);
    }

    it 'leaves non-matching rows alone', {
      expect(BkWidget.where({ name => 'c' }).first.active).to.eq(False);
    }
  }

  context 'Model.update-all', {
    my $n;

    before-each {
      BkWidget.create({ name => 'a', qty => 1 });
      BkWidget.create({ name => 'b', qty => 2 });

      $n = BkWidget.update-all(active => True);
    }

    it 'touches every row', {
      expect($n).to.eq(2);
    }

    it 'persists the change', {
      expect(BkWidget.where({ active => True }).count).to.eq(2);
    }
  }

  context 'delete-all on a where-scoped relation', {
    my $n;

    before-each {
      BkWidget.create({ name => 'a' });
      BkWidget.create({ name => 'b' });
      BkWidget.create({ name => 'c' });

      $n = BkWidget.where({ name => 'b' }).delete-all;
    }

    it 'returns the row count', {
      expect($n).to.eq(1);
    }

    it 'leaves only the unmatched rows', {
      expect(BkWidget.count).to.eq(2);
    }

    it 'removes the targeted row', {
      expect(BkWidget.where({ name => 'b' }).count).to.eq(0);
    }
  }

  context 'destroy-by', {
    my $n;

    before-each {
      BkWidget.create({ name => 'a' });
      BkWidget.create({ name => 'b' });

      $n = BkWidget.destroy-by({ name => 'a' });
    }

    it 'returns the count', {
      expect($n).to.eq(1);
    }

    it 'removes the matching rows', {
      expect(BkWidget.count).to.eq(1);
    }
  }

  context 'delete-by', {
    my $n;

    before-each {
      BkWidget.create({ name => 'a' });
      BkWidget.create({ name => 'b' });

      $n = BkWidget.delete-by({ name => 'a' });
    }

    it 'returns the count', {
      expect($n).to.eq(1);
    }

    it 'removes the matching rows', {
      expect(BkWidget.count).to.eq(1);
    }
  }

  context 'Model.update with multiple ids', {
    my @updated;
    my $a;
    my $b;

    before-each {
      $a       = BkWidget.create({ name => 'a', qty => 1 });
      $b       = BkWidget.create({ name => 'b', qty => 2 });
      @updated = BkWidget.update([$a.id, $b.id], { qty => 99 });
    }

    it 'returns the list of updated objects', {
      expect(@updated.elems).to.eq(2);
    }

    it 'wrote the first record', {
      expect(BkWidget.find($a.id).qty).to.eq(99);
    }

    it 'wrote the second record', {
      expect(BkWidget.find($b.id).qty).to.eq(99);
    }
  }

  context 'update-counters single id', {
    my $w;

    before-each {
      $w = BkWidget.create({ name => 'a', qty => 10 });
    }

    it 'returns the affected count', {
      my $n = BkWidget.update-counters($w.id, qty => 5);

      expect($n).to.eq(1);
    }

    it 'adds the increment', {
      BkWidget.update-counters($w.id, qty => 5);

      expect(BkWidget.find($w.id).qty).to.eq(15);
    }

    it 'subtracts a negative increment', {
      BkWidget.update-counters($w.id, qty => 5);
      BkWidget.update-counters($w.id, qty => -3);

      expect(BkWidget.find($w.id).qty).to.eq(12);
    }
  }

  context 'update-counters with multiple ids', {
    my $a;
    my $b;
    my $n;

    before-each {
      $a = BkWidget.create({ name => 'a', qty => 1 });
      $b = BkWidget.create({ name => 'b', qty => 2 });
      $n = BkWidget.update-counters([$a.id, $b.id], qty => 10);
    }

    it 'batches both rows', {
      expect($n).to.eq(2);
    }

    it 'updates the first row', {
      expect(BkWidget.find($a.id).qty).to.eq(11);
    }

    it 'updates the second row', {
      expect(BkWidget.find($b.id).qty).to.eq(12);
    }
  }

  context 'insert / insert-all', {
    my $id;
    my @ids;

    before-each {
      $id  = BkWidget.insert({ name => 'x', qty => 1 });
      @ids = BkWidget.insert-all([
        { name => 'y', qty => 2 },
        { name => 'z', qty => 3 },
      ]);
    }

    it 'insert returns an id', {
      expect($id).to.be-greater-than(0);
    }

    it 'insert persisted the row', {
      my $w = BkWidget.find($id);

      expect($w.name).to.eq('x');
    }

    it 'insert-all returns the ids list', {
      expect(@ids.elems).to.eq(2);
    }

    it 'insert-all wrote the first row', {
      expect(BkWidget.find(@ids[0]).name).to.eq('y');
    }

    it 'insert-all wrote the second row', {
      expect(BkWidget.find(@ids[1]).name).to.eq('z');
    }
  }

  context 'insert on unique-index conflict', {
    my $id1;
    my $id2;

    before-each {
      $id1 = BkWidget.insert({ name => 'dup', qty => 1 });
      $id2 = BkWidget.insert({ name => 'dup', qty => 9 });
    }

    it 'first insert created the row', {
      expect($id1).to.be-greater-than(0);
    }

    it 'second insert silently skipped (returned 0)', {
      expect($id2).to.eq(0);
    }

    it 'left no duplicate', {
      expect(BkWidget.where({ name => 'dup' }).count).to.eq(1);
    }
  }

  context 'insert-bang', {
    it 'raises on unique violation', {
      BkWidget.insert({ name => 'dup' });

      expect({ BkWidget.insert-bang({ name => 'dup' }) }).to.raise-error;
    }
  }

  context 'insert-all-bang', {
    it 'raises on conflict', {
      BkWidget.insert({ name => 'taken' });

      expect({ BkWidget.insert-all-bang([{ name => 'taken' }]) }).to.raise-error;
    }
  }

  context 'upsert', {
    my $orig;

    before-each {
      $orig = BkWidget.create({ name => 'u', qty => 1 });
    }

    it 'returns the affected count when updating existing', {
      my $n = BkWidget.upsert({ id => $orig.id, name => 'u2', qty => 42 });

      expect($n >= 1).to.be-truthy;
    }

    it 'updates the existing qty', {
      BkWidget.upsert({ id => $orig.id, name => 'u2', qty => 42 });

      expect(BkWidget.find($orig.id).qty).to.eq(42);
    }

    it 'updates the existing name', {
      BkWidget.upsert({ id => $orig.id, name => 'u2', qty => 42 });

      expect(BkWidget.find($orig.id).name).to.eq('u2');
    }

    it 'inserts a fresh row when unique-by does not match', {
      my $n2 = BkWidget.upsert({ name => 'fresh', qty => 7 }, unique-by => ['name']);

      expect($n2).to.eq(1);
    }

    it 'wrote the fresh row', {
      BkWidget.upsert({ name => 'fresh', qty => 7 }, unique-by => ['name']);

      expect(BkWidget.where({ name => 'fresh' }).first.qty).to.eq(7);
    }
  }

  context 'upsert-all', {
    my $n;

    before-each {
      BkWidget.create({ name => 'p', qty => 1 });

      $n = BkWidget.upsert-all(
        [
          { name => 'p', qty => 100 },
          { name => 'q', qty => 200 },
        ],
        unique-by => ['name'],
      );
    }

    it 'returns the count', {
      expect($n).to.be-greater-than-or-equal-to(1);
    }

    it 'updated the existing row', {
      expect(BkWidget.where({ name => 'p' }).first.qty).to.eq(100);
    }

    it 'inserted the new row', {
      expect(BkWidget.where({ name => 'q' }).first.qty).to.eq(200);
    }
  }

  context 'is-none short-circuits set-based ops', {
    before-each {
      BkWidget.create({ name => 'a' });
    }

    it 'none.update-all returns 0', {
      expect(BkWidget.none.update-all(qty => 99)).to.eq(0);
    }

    it 'none.delete-all returns 0', {
      expect(BkWidget.none.delete-all).to.eq(0);
    }

    it 'none.update-counters returns 0', {
      expect(BkWidget.none.update-counters(qty => 1)).to.eq(0);
    }

    it 'leaves data intact', {
      BkWidget.none.update-all(qty => 99);
      BkWidget.none.delete-all;
      BkWidget.none.update-counters(qty => 1);

      expect(BkWidget.count).to.eq(1);
    }
  }
}
