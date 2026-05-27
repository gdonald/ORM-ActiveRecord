use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS dt_widgets');
  $adapter.ddl-create-table('dt_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
}

class DtWidget is Model {
  method table-name { 'dt_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS dt_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'dirty tracking', {
  context 'fresh saved record', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'A', qty => 1 });
    }

    it 'is not changed', {
      expect($w.is-changed).to.be-falsy;
    }

    it 'has an empty changed list', {
      expect($w.changed.elems).to.eq(0);
    }

    it 'has an empty changes hash', {
      expect($w.changes.keys.elems).to.eq(0);
    }
  }

  context 'after a single attribute mutation', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'A', qty => 1 });
      $w.name = 'B';
    }

    it 'is-changed is True', {
      expect($w.is-changed).to.be-truthy;
    }

    it 'changed lists the mutated attribute', {
      expect($w.changed.Set === <name>.Set).to.be-truthy;
    }

    it 'changes maps name to [old, new]', {
      expect($w.changes<name>).to.eq(['A', 'B']);
    }

    it 'changed-attributes maps name to original value', {
      expect($w.changed-attributes<name>).to.eq('A');
    }
  }

  context 'after a second attribute mutation', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'A', qty => 1 });
      $w.name = 'B';
      $w.qty = 7;
    }

    it 'changed lists both attributes', {
      expect($w.changed.Set === <name qty>.Set).to.be-truthy;
    }

    it 'changes maps qty to [old, new]', {
      expect($w.changes<qty>).to.eq([1, 7]);
    }
  }

  context 'per-attribute predicates', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'C', qty => 2 });
    }

    it 'reports unchanged attribute as not changed', {
      expect($w.is-attribute-changed('name')).to.be-falsy;
    }

    it 'reports changed attribute as changed', {
      $w.name = 'D';

      expect($w.is-attribute-changed('name')).to.be-truthy;
    }

    it 'attribute-was returns the original', {
      $w.name = 'D';

      expect($w.attribute-was('name')).to.eq('C');
    }

    it 'attribute-change returns [old, new]', {
      $w.name = 'D';

      expect($w.attribute-change('name')).to.eq(['C', 'D']);
    }

    it 'unchanged attribute is not changed', {
      expect($w.is-attribute-changed('qty')).to.be-falsy;
    }

    it 'attribute-was returns current value for unchanged', {
      expect($w.attribute-was('qty')).to.eq(2);
    }

    it 'attribute-change is undefined for unchanged', {
      expect($w.attribute-change('qty').defined).to.be-falsy;
    }
  }

  context 'FALLBACK-dispatched dynamic methods', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'E', qty => 3 });
      $w.name = 'F';
    }

    it 'dispatches is-<attr>-changed', {
      expect($w.is-name-changed).to.be-truthy;
    }

    it 'dispatches <attr>-was', {
      expect($w.name-was).to.eq('E');
    }

    it 'dispatches <attr>-change', {
      expect($w.name-change).to.eq(['E', 'F']);
    }

    it 'returns False for an unchanged attribute', {
      expect($w.is-qty-changed).to.be-falsy;
    }
  }

  context 'attribute-will-change', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'G' });
    }

    it 'shows no diff before will-change', {
      expect($w.is-changed).to.be-falsy;
    }

    it 'forces is-changed True', {
      $w.attribute-will-change('name');

      expect($w.is-changed).to.be-truthy;
    }

    it 'forces per-attribute changed True', {
      $w.attribute-will-change('name');

      expect($w.is-attribute-changed('name')).to.be-truthy;
    }

    it 'dispatches <attr>-will-change via FALLBACK', {
      my $w2 = DtWidget.create({ name => 'H' });
      $w2.name-will-change;

      expect($w2.is-changed).to.be-truthy;
    }
  }

  context 'previous-changes after insert', {
    my $w;

    before-each {
      $w = DtWidget.build({ name => 'I', qty => 4 });
      $w.save;
    }

    it 'has a previous-changes entry for name', {
      expect($w.previous-changes<name>:exists).to.be-truthy;
    }

    it 'captures [default, new] for insert', {
      expect($w.previous-changes<name>).to.eq(['', 'I']);
    }

    it 'captures the saved-change pair after update', {
      $w.name = 'J';
      $w.save;

      expect($w.previous-changes<name>).to.eq(['I', 'J']);
    }

    it 'is clean after save', {
      $w.name = 'J';
      $w.save;

      expect($w.is-changed).to.be-falsy;
    }

    it 'reports no attribute as changed after save', {
      $w.name = 'J';
      $w.save;

      expect($w.is-attribute-changed('name')).to.be-falsy;
    }
  }

  context 'saved-change-to / before-last-save', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'K' });
      $w.name = 'L';
      $w.save;
    }

    it 'is-saved-change-to is True for changed attribute', {
      expect($w.is-saved-change-to('name')).to.be-truthy;
    }

    it 'saved-change-to returns the pair', {
      expect($w.saved-change-to('name')).to.eq(['K', 'L']);
    }

    it '<attr>-before-last-save returns the pre-save value', {
      expect($w.name-before-last-save).to.eq('K');
    }

    it 'is-saved-change-to-<attr> dispatches via FALLBACK', {
      expect($w.is-saved-change-to-name).to.be-truthy;
    }

    it 'saved-change-to-<attr> dispatches via FALLBACK', {
      expect($w.saved-change-to-name).to.eq(['K', 'L']);
    }

    it 'unchanged column is not saved-changed', {
      expect($w.is-saved-change-to('qty')).to.be-falsy;
    }

    it 'saved-change-to is undefined for unchanged column', {
      expect($w.saved-change-to('qty').defined).to.be-falsy;
    }
  }

  context 'restore-attributes', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'M', qty => 5 });
      $w.name = 'N';
      $w.qty = 99;
    }

    it 'is-changed is True after edit', {
      expect($w.is-changed).to.be-truthy;
    }

    it 'restores the original name', {
      $w.restore-attributes;

      expect($w.name).to.eq('M');
    }

    it 'restores the original qty', {
      $w.restore-attributes;

      expect($w.qty).to.eq(5);
    }

    it 'clears the dirty flag', {
      $w.restore-attributes;

      expect($w.is-changed).to.be-falsy;
    }
  }

  context 'restore-<attr>', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'M2', qty => 5 });
      $w.name = 'O';
      $w.restore-name;
    }

    it 'restores the single attribute', {
      expect($w.name).to.eq('M2');
    }

    it 'clears the per-attribute changed flag', {
      expect($w.is-attribute-changed('name')).to.be-falsy;
    }
  }

  context 'reset-<attr>', {
    it 'is an alias for restore-<attr>', {
      my $w = DtWidget.create({ name => 'P' });
      $w.name = 'Q';
      $w.reset-name;

      expect($w.name).to.eq('P');
    }
  }

  context 'reload', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'R', qty => 6 });
      my $w-copy = DtWidget.find($w.id);
      $w-copy.name = 'R-edited';
      $w-copy.save;
    }

    it 'has stale value before reload', {
      expect($w.name).to.eq('R');
    }

    it 'pulls latest values from the DB', {
      $w.reload;

      expect($w.name).to.eq('R-edited');
    }

    it 'clears the dirty state', {
      $w.reload;

      expect($w.is-changed).to.be-falsy;
    }
  }

  context 'save flushes dirty state', {
    my $w;

    before-each {
      $w = DtWidget.create({ name => 'S' });
      $w.name = 'T';
    }

    it 'is dirty before save', {
      expect($w.is-changed).to.be-truthy;
    }

    it 'is clean after save', {
      $w.save;

      expect($w.is-changed).to.be-falsy;
    }

    it 'preserves previous-changes after save', {
      $w.save;

      expect($w.previous-changes<name>).to.eq(['S', 'T']);
    }
  }
}
