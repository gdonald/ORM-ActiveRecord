use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class FiUser is Model {
  method table-name { 'users' }
}

describe 'find-or-initialize-by', {
  before-each {
    FiUser.destroy-all;
    FiUser.create({fname => 'Alice', lname => 'A'});
  }

  after-each {
    FiUser.destroy-all;
  }

  context 'returns existing record when found', {
    it 'returns the existing row', {
      my $found = FiUser.find-or-initialize-by({fname => 'Alice'});

      expect($found.defined && $found.id > 0).to.be-truthy;
    }

    it 'does not create a duplicate row', {
      FiUser.find-or-initialize-by({fname => 'Alice'});

      expect(FiUser.where({fname => 'Alice'}).count).to.eq(1);
    }
  }

  context 'builds an unsaved new record when not found', {
    it 'returns an in-memory object', {
      my $built = FiUser.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.defined).to.be-truthy;
    }

    it 'is not persisted', {
      my $built = FiUser.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.id).to.eq(0);
    }

    it 'assigns attrs on the unsaved record', {
      my $built = FiUser.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect($built.fname eq 'Bobby' && $built.lname eq 'B').to.be-truthy;
    }

    it 'does not insert', {
      FiUser.find-or-initialize-by({fname => 'Bobby', lname => 'B'});

      expect(FiUser.where({fname => 'Bobby'}).count).to.eq(0);
    }
  }

  context 'relation-scoped', {
    it 'returns an unsaved record', {
      my $scoped = FiUser.where({lname => 'Z'}).create-with({fname => 'Default'})
                       .find-or-initialize-by({fname => 'Custom'});

      expect($scoped.defined && $scoped.id == 0).to.be-truthy;
    }

    it 'merges attrs: find params win, where conditions provide defaults', {
      my $scoped = FiUser.where({lname => 'Z'}).create-with({fname => 'Default'})
                       .find-or-initialize-by({fname => 'Custom'});

      expect($scoped.fname eq 'Custom' && $scoped.lname eq 'Z').to.be-truthy;
    }
  }
}
