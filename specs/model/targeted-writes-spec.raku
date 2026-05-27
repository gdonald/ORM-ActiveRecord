use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS tw_widgets');
  $adapter.ddl-create-table('tw_widgets', [
    name   => { :string, limit => 64 },
    qty    => { :integer, default => 0 },
    active => { :boolean, default => False },
  ]);
  $adapter.ddl-add-timestamps('tw_widgets');
}

class TwWidget is Model {
  method table-name { 'tw_widgets' }

  has Int $.before-save-count is rw = 0;
  has Int $.before-update-count is rw = 0;

  submethod BUILD {
    self.validate: 'name', { :presence };
    self.before-save:   -> { self.before-save-count++   };
    self.before-update: -> { self.before-update-count++ };
  }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS tw_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'targeted writes', {
  context 'update-column bypasses validations, callbacks, timestamps', {
    my $w;
    my $before-count;
    my $ua-posix;

    before-each {
      $w = TwWidget.create({ name => 'A', qty => 1 });
      $before-count = $w.before-update-count;
      $ua-posix = $w.updated_at.posix.Int;

      sleep 1.1;
    }

    it 'update-column returns True', {
      expect($w.update-column('qty', 42)).to.be-truthy;
    }

    it 'updates the in-memory value', {
      $w.update-column('qty', 42);

      expect($w.qty).to.eq(42);
    }

    it 'skips the before-update callback', {
      $w.update-column('qty', 42);

      expect($w.before-update-count).to.eq($before-count);
    }

    it 'persists to the DB', {
      $w.update-column('qty', 42);
      my $w2 = TwWidget.find($w.id);

      expect($w2.qty).to.eq(42);
    }

    it 'does not bump updated_at', {
      $w.update-column('qty', 42);
      my $w2 = TwWidget.find($w.id);

      expect($w2.updated_at.posix.Int).to.eq($ua-posix);
    }

    it 'leaves the record clean', {
      $w.update-column('qty', 42);

      expect($w.is-changed).to.be-falsy;
    }
  }

  context 'update-columns', {
    my $w;

    before-each {
      $w = TwWidget.create({ name => 'B', qty => 1 });
    }

    it 'returns True', {
      expect($w.update-columns({ name => 'B2', qty => 9 })).to.be-truthy;
    }

    it 'persists both columns', {
      $w.update-columns({ name => 'B2', qty => 9 });
      my $w2 = TwWidget.find($w.id);

      expect($w2.name eq 'B2' && $w2.qty == 9).to.be-truthy;
    }
  }

  context 'update-attribute runs callbacks but skips validations', {
    my $w;
    my $before-save;

    before-each {
      $w = TwWidget.create({ name => 'C' });
      $before-save = $w.before-save-count;
    }

    it 'returns True', {
      expect($w.update-attribute('qty', 7)).to.be-truthy;
    }

    it 'sets the value', {
      $w.update-attribute('qty', 7);

      expect($w.qty).to.eq(7);
    }

    it 'runs the before-save callback', {
      $w.update-attribute('qty', 7);

      expect($w.before-save-count).to.be-greater-than($before-save);
    }

    it 'skips validation (returns True for invalid value)', {
      expect($w.update-attribute('name', '')).to.be-truthy;
    }

    it 'persists the invalid value', {
      $w.update-attribute('name', '');

      expect(TwWidget.find($w.id).name).to.eq('');
    }
  }

  context 'touch', {
    my $w;
    my $ua-posix;

    before-each {
      $w = TwWidget.create({ name => 'D' });
      $ua-posix = $w.updated_at.posix.Int;
      sleep 1.1;
    }

    it 'returns True', {
      expect($w.touch).to.be-truthy;
    }

    it 'bumps updated_at', {
      $w.touch;
      my $w2 = TwWidget.find($w.id);

      expect($w2.updated_at.posix.Int).to.be-greater-than($ua-posix);
    }
  }

  context 'touch-all on a relation', {
    my $before1;
    my $n;

    before-each {
      TwWidget.destroy-all;
      TwWidget.create({ name => 'X1' });
      TwWidget.create({ name => 'X2' });
      $before1 = TwWidget.where({ name => 'X1' }).first.updated_at.posix.Int;
      sleep 1.1;
      $n = TwWidget.where({ name => 'X1' }).touch-all;
    }

    it 'returns the affected count', {
      expect($n).to.eq(1);
    }

    it 'bumps the matching row', {
      expect(TwWidget.where({ name => 'X1' }).first.updated_at.posix.Int).to.be-greater-than($before1);
    }
  }

  context 'increment / decrement', {
    my $w;

    before-each {
      $w = TwWidget.create({ name => 'E', qty => 5 });
    }

    it 'increment defaults to +1', {
      $w.increment('qty');

      expect($w.qty).to.eq(6);
    }

    it 'increment(name, n) adds n', {
      $w.increment('qty');
      $w.increment('qty', 10);

      expect($w.qty).to.eq(16);
    }

    it 'leaves the record dirty (in-memory only)', {
      $w.increment('qty');

      expect($w.is-changed).to.be-truthy;
    }

    it 'decrement(name, n) subtracts n', {
      $w.increment('qty');
      $w.increment('qty', 10);
      $w.decrement('qty', 6);

      expect($w.qty).to.eq(10);
    }
  }

  context 'increment-or-die / decrement-or-die persist', {
    it 'increment-or-die persists +1', {
      my $w = TwWidget.create({ name => 'F', qty => 0 });
      $w.increment-or-die('qty');

      expect(TwWidget.find($w.id).qty).to.eq(1);
    }

    it 'decrement-or-die persists -1', {
      my $w = TwWidget.create({ name => 'F2', qty => 1 });
      $w.decrement-or-die('qty', 1);

      expect(TwWidget.find($w.id).qty).to.eq(0);
    }
  }

  context 'toggle / toggle-or-die', {
    my $w;

    before-each {
      $w = TwWidget.create({ name => 'G', active => False });
    }

    it 'toggle flips the boolean in memory', {
      $w.toggle('active');

      expect($w.active).to.eq(True);
    }

    it 'leaves the record dirty (in-memory only)', {
      $w.toggle('active');

      expect($w.is-changed).to.be-truthy;
    }

    it 'toggle-or-die persists the flip', {
      $w.toggle('active');
      $w.toggle-or-die('active');

      expect(TwWidget.find($w.id).active).to.eq(False);
    }
  }

  context 'frozen and readonly guards on targeted writes', {
    it 'update-column dies after destroy', {
      my $w = TwWidget.create({ name => 'H' });
      $w.destroy;

      expect({ $w.update-column('qty', 1) }).to.raise-error;
    }

    it 'touch dies after destroy', {
      my $w = TwWidget.create({ name => 'H2' });
      $w.destroy;

      expect({ $w.touch }).to.raise-error;
    }

    it 'update-column dies on a readonly record', {
      my $w = TwWidget.create({ name => 'I' });
      $w.make-readonly;

      expect({ $w.update-column('qty', 1) }).to.raise-error;
    }
  }

  context 'save with :!validate', {
    my $w;

    before-each {
      $w = TwWidget.create({ name => 'J' });
      $w.name = '';
    }

    it 'save with validations fails on an invalid record', {
      expect($w.save).to.be-falsy;
    }

    it 'save(:!validate) bypasses validation', {
      expect($w.save(:!validate)).to.be-truthy;
    }

    it 'save(:!validate) persists the invalid value', {
      $w.save(:!validate);

      expect(TwWidget.find($w.id).name).to.eq('');
    }
  }

  context 'save with :!touch', {
    my $w;
    my $ua-posix;

    before-each {
      $w = TwWidget.create({ name => 'K' });
      $ua-posix = $w.updated_at.posix.Int;
      sleep 1.1;
      $w.qty = 100;
    }

    it 'still saves', {
      expect($w.save(:!touch)).to.be-truthy;
    }

    it 'does not bump updated_at', {
      $w.save(:!touch);

      expect(TwWidget.find($w.id).updated_at.posix.Int).to.eq($ua-posix);
    }
  }
}
