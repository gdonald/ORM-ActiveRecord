use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use Models::Belonging;
use Models::Singleton;

%*ENV<DISABLE-SQL-LOG> = True;

class DestroyOwner is Model {
  submethod BUILD {
    self.has-many: belongings => %(class => Belonging, foreign-key => 'owner_id', dependent => 'destroy');
  }
}

class DeleteOwner is Model {
  submethod BUILD {
    self.has-many: belongings => %(class => Belonging, foreign-key => 'owner_id', dependent => 'delete-all');
  }
}

class NullifyOwner is Model {
  submethod BUILD {
    self.has-many: belongings => %(class => Belonging, foreign-key => 'owner_id', dependent => 'nullify');
  }
}

class RestErrOwner is Model {
  submethod BUILD {
    self.has-many: belongings => %(class => Belonging, foreign-key => 'owner_id', dependent => 'restrict-with-error');
  }
}

class RestExcOwner is Model {
  submethod BUILD {
    self.has-many: belongings => %(class => Belonging, foreign-key => 'owner_id', dependent => 'restrict-with-exception');
  }
}

class OneDestroyOwner is Model {
  submethod BUILD {
    self.has-one: singleton => %(class => Singleton, foreign-key => 'owner_id', dependent => 'destroy');
  }
}

class OneNullifyOwner is Model {
  submethod BUILD {
    self.has-one: singleton => %(class => Singleton, foreign-key => 'owner_id', dependent => 'nullify');
  }
}

class OneRestExcOwner is Model {
  submethod BUILD {
    self.has-one: singleton => %(class => Singleton, foreign-key => 'owner_id', dependent => 'restrict-with-exception');
  }
}

sub belonging-count(--> Int) {
  DB.shared.exec('SELECT COUNT(*) FROM belongings')[0][0].Int;
}

sub singleton-count(--> Int) {
  DB.shared.exec('SELECT COUNT(*) FROM singletons')[0][0].Int;
}

describe 'dependent option', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'has-many destroy', {
    it 'parent.destroy returns True', {
      my $owner = DestroyOwner.create({name => 'destroy'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      expect($owner.destroy).to.be-truthy;
    }

    it 'removes all children', {
      my $owner = DestroyOwner.create({name => 'destroy'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      Belonging.create({owner_id => $owner.id, label => 'b'});
      $owner.destroy;
      expect(belonging-count()).to.eq(0);
    }

    it 'removes parent', {
      my $owner = DestroyOwner.create({name => 'destroy'});
      $owner.destroy;
      expect(DestroyOwner.count).to.eq(0);
    }

    it 'fires child before-destroy callbacks', {
      Belonging.reset-destroy-count;
      my $owner = DestroyOwner.create({name => 'destroy-cb'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect(Belonging.destroy-count).to.eq(1);
    }
  }

  context 'has-many delete-all', {
    it 'parent.destroy returns True', {
      my $owner = DeleteOwner.create({name => 'delete-all'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      expect($owner.destroy).to.be-truthy;
    }

    it 'removes all children', {
      my $owner = DeleteOwner.create({name => 'delete-all'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      Belonging.create({owner_id => $owner.id, label => 'b'});
      $owner.destroy;
      expect(belonging-count()).to.eq(0);
    }

    it 'does NOT fire child before-destroy callbacks', {
      Belonging.reset-destroy-count;
      my $owner = DeleteOwner.create({name => 'delete-all'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect(Belonging.destroy-count).to.eq(0);
    }
  }

  context 'has-many nullify', {
    it 'parent.destroy returns True', {
      my $owner = NullifyOwner.create({name => 'nullify'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      expect($owner.destroy).to.be-truthy;
    }

    it 'leaves children rows', {
      my $owner = NullifyOwner.create({name => 'nullify'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      Belonging.create({owner_id => $owner.id, label => 'b'});
      $owner.destroy;
      expect(belonging-count()).to.eq(2);
    }

    it 'nulls every child owner_id', {
      my $owner = NullifyOwner.create({name => 'nullify'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      my @rows = DB.shared.exec('SELECT owner_id FROM belongings');
      expect(@rows.map({ !$_[0].defined }).all.so).to.be-truthy;
    }
  }

  context 'has-many restrict-with-error', {
    it 'destroy returns False when children exist', {
      my $owner = RestErrOwner.create({name => 'restrict-err'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      expect($owner.destroy).to.be-falsy;
    }

    it 'does NOT remove parent', {
      my $owner = RestErrOwner.create({name => 'restrict-err'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect(RestErrOwner.count).to.eq(1);
    }

    it 'does NOT remove children', {
      my $owner = RestErrOwner.create({name => 'restrict-err'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect(belonging-count()).to.eq(1);
    }

    it 'records an error', {
      my $owner = RestErrOwner.create({name => 'restrict-err'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect($owner.errors.errors.elems).to.be-greater-than(0);
    }

    it 'error mentions the association', {
      my $owner = RestErrOwner.create({name => 'restrict-err'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      $owner.destroy;
      expect($owner.errors.errors[0].message).to.match(/'belongings'/);
    }

    context 'no children', {
      it 'destroy succeeds', {
        my $owner = RestErrOwner.create({name => 'restrict-err-empty'});
        expect($owner.destroy).to.be-truthy;
      }

      it 'parent is removed', {
        my $owner = RestErrOwner.create({name => 'restrict-err-empty'});
        $owner.destroy;
        expect(RestErrOwner.count).to.eq(0);
      }
    }
  }

  context 'has-many restrict-with-exception', {
    it 'raises when children exist', {
      my $owner = RestExcOwner.create({name => 'restrict-exc'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      expect({ $owner.destroy }).to.raise-error;
    }

    it 'raises X::DeleteRestrictionError', {
      my $owner = RestExcOwner.create({name => 'restrict-exc-2'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      my $err;
      try { $owner.destroy; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::DeleteRestrictionError');
    }

    it 'does NOT remove parent', {
      my $owner = RestExcOwner.create({name => 'restrict-exc-3'});
      Belonging.create({owner_id => $owner.id, label => 'a'});
      try { $owner.destroy }
      expect(RestExcOwner.count).to.eq(1);
    }

    it 'destroy works when no children', {
      my $owner = RestExcOwner.create({name => 'restrict-exc-empty'});
      expect($owner.destroy).to.be-truthy;
    }
  }

  context 'has-one destroy', {
    it 'parent.destroy returns True', {
      my $owner = OneDestroyOwner.create({name => 'has-one-destroy'});
      Singleton.create({owner_id => $owner.id, label => 'only'});
      expect($owner.destroy).to.be-truthy;
    }

    it 'child is removed', {
      my $owner = OneDestroyOwner.create({name => 'has-one-destroy'});
      Singleton.create({owner_id => $owner.id, label => 'only'});
      $owner.destroy;
      expect(singleton-count()).to.eq(0);
    }
  }

  context 'has-one nullify', {
    it 'parent.destroy returns True', {
      my $owner = OneNullifyOwner.create({name => 'has-one-nullify'});
      Singleton.create({owner_id => $owner.id, label => 'only'});
      expect($owner.destroy).to.be-truthy;
    }

    it 'child remains', {
      my $owner = OneNullifyOwner.create({name => 'has-one-nullify'});
      Singleton.create({owner_id => $owner.id, label => 'only'});
      $owner.destroy;
      expect(singleton-count()).to.eq(1);
    }
  }

  context 'has-one restrict-with-exception', {
    it 'raises when child exists', {
      my $owner = OneRestExcOwner.create({name => 'has-one-restrict'});
      Singleton.create({owner_id => $owner.id, label => 'only'});
      expect({ $owner.destroy }).to.raise-error;
    }
  }
}
