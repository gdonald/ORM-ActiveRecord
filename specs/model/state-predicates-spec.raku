use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS sp_widgets');
  $adapter.ddl-create-table('sp_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
}

class SpWidget is Model {
  method table-name { 'sp_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS sp_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'state predicates', {
  context 'is-new-record / is-persisted / is-destroyed lifecycle', {
    context 'on a built record', {
      my $w;

      before-each {
        $w = SpWidget.build({ name => 'A' });
      }

      it 'is a new record', {
        expect($w.is-new-record).to.be-truthy;
      }

      it 'is not persisted', {
        expect($w.is-persisted).to.be-falsy;
      }

      it 'is not destroyed', {
        expect($w.is-destroyed).to.be-falsy;
      }
    }

    context 'after save', {
      my $w;

      before-each {
        $w = SpWidget.build({ name => 'A' });
        $w.save;
      }

      it 'is no longer a new record', {
        expect($w.is-new-record).to.be-falsy;
      }

      it 'is persisted', {
        expect($w.is-persisted).to.be-truthy;
      }

      it 'is not destroyed', {
        expect($w.is-destroyed).to.be-falsy;
      }
    }

    context 'after destroy', {
      my $w;

      before-each {
        $w = SpWidget.build({ name => 'A' });
        $w.save;
        $w.destroy;
      }

      it 'is not a new record', {
        expect($w.is-new-record).to.be-falsy;
      }

      it 'is not persisted', {
        expect($w.is-persisted).to.be-falsy;
      }

      it 'is destroyed', {
        expect($w.is-destroyed).to.be-truthy;
      }
    }
  }

  context 'was-new-record', {
    it 'is False for a built record', {
      my $w = SpWidget.build({ name => 'B' });

      expect($w.was-new-record).to.be-falsy;
    }

    it 'is True after the first save', {
      my $w = SpWidget.build({ name => 'B' });
      $w.save;

      expect($w.was-new-record).to.be-truthy;
    }

    it 'is False after a subsequent save', {
      my $w = SpWidget.build({ name => 'B' });
      $w.save;
      $w.name = 'B2';
      $w.save;

      expect($w.was-new-record).to.be-falsy;
    }
  }

  context 'was-persisted', {
    it 'is False for a built record', {
      my $w = SpWidget.build({ name => 'C' });

      expect($w.was-persisted).to.be-falsy;
    }

    it 'is still False for a persisted record', {
      my $w = SpWidget.build({ name => 'C' });
      $w.save;

      expect($w.was-persisted).to.be-falsy;
    }

    it 'is True after destroying a persisted record', {
      my $w = SpWidget.build({ name => 'C' });
      $w.save;
      $w.destroy;

      expect($w.was-persisted).to.be-truthy;
    }
  }

  context 'destroy on an unsaved record', {
    my $w;

    before-each {
      $w = SpWidget.build({ name => 'D' });
      $w.destroy;
    }

    it 'does not set was-persisted', {
      expect($w.was-persisted).to.be-falsy;
    }

    it 'does not mark the record destroyed', {
      expect($w.is-destroyed).to.be-falsy;
    }
  }

  context 'frozen state after destroy', {
    my $w;

    before-each {
      $w = SpWidget.create({ name => 'E' });
      $w.destroy;
    }

    it 'is-frozen is True', {
      expect($w.is-frozen).to.be-truthy;
    }

    it 'write-attribute dies', {
      expect({ $w.write-attribute('name', 'X') }).to.raise-error;
    }

    it 'assign-attributes dies', {
      expect({ $w.assign-attributes({ name => 'X' }) }).to.raise-error;
    }

    it 'attributes= dies', {
      expect({ $w.attributes = { name => 'X' } }).to.raise-error;
    }

    it '[]= dies', {
      expect({ $w<name> = 'X' }).to.raise-error;
    }

    it 'save dies', {
      expect({ $w.save }).to.raise-error;
    }

    it 'read-attribute still works', {
      expect($w.read-attribute('name')).to.eq('E');
    }

    it '[] still works', {
      expect($w<name>).to.eq('E');
    }
  }

  context 'is-readonly', {
    my $w;

    before-each {
      $w = SpWidget.build({ name => 'F' });
    }

    it 'is False for a fresh record', {
      expect($w.is-readonly).to.be-falsy;
    }

    it 'flips True after make-readonly', {
      $w.make-readonly;

      expect($w.is-readonly).to.be-truthy;
    }

    it 'save raises on a readonly record', {
      $w.make-readonly;

      expect({ $w.save }).to.raise-error;
    }
  }

  context 'specific exception types', {
    it 'frozen write raises X::FrozenRecord', {
      my $w = SpWidget.create({ name => 'G' });
      $w.destroy;

      expect({ $w.write-attribute('name', 'X') }).to.raise-error(X::FrozenRecord);
    }

    it 'readonly save raises X::ReadOnlyRecord', {
      my $w = SpWidget.build({ name => 'H' });
      $w.make-readonly;

      expect({ $w.save }).to.raise-error(X::ReadOnlyRecord);
    }
  }
}
