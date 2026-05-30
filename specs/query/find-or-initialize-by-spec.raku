use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'find-or-initialize-by', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'A'});
  }

  after-each {
    User.destroy-all;
  }

  context 'returns existing record when found', {
    it 'returns the existing row', {
      my $found = User.find-or-initialize-by({fname => 'Alice'});

      expect($found.defined && $found.id > 0).to.be-truthy;
    }

    it 'does not create a duplicate row', {
      User.find-or-initialize-by({fname => 'Alice'});

      expect(User.where({fname => 'Alice'}).count).to.eq(1);
    }
  }

  context 'builds an unsaved new record when not found', {
    it 'returns an in-memory object', {
      my $built = User.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.defined).to.be-truthy;
    }

    it 'is not persisted', {
      my $built = User.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.id).to.eq(0);
    }

    it 'assigns attrs on the unsaved record', {
      my $built = User.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.fname eq 'Bobby' && $built.lname eq 'B').to.be-truthy;
    }

    it 'does not insert', {
      User.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect(User.where({fname => 'Bobby'}).count).to.eq(0);
    }
  }

  context 'relation-scoped', {
    it 'returns an unsaved record', {
      my $scoped = User.where({lname => 'Z'}).create-with({fname => 'Default'})
                       .find-or-initialize-by({fname => 'Custom'});

      expect($scoped.defined && $scoped.id == 0).to.be-truthy;
    }

    it 'merges attrs: find params win, where conditions provide defaults', {
      my $scoped = User.where({lname => 'Z'}).create-with({fname => 'Default'})
                       .find-or-initialize-by({fname => 'Custom'});

      expect($scoped.fname eq 'Custom' && $scoped.lname eq 'Z').to.be-truthy;
    }
  }
}
