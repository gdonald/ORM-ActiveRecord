use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class IdUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

describe 'is-dirty', {
  after-each {
    IdUser.destroy-all;
  }

  context 'a freshly created record', {
    it 'is not dirty', {
      my $user = IdUser.create({fname => 'Fred'});

      expect($user.is-dirty).to.be-falsy;
    }
  }

  context 'after mutating an attribute', {
    it 'becomes dirty', {
      my $user = IdUser.create({fname => 'Fred'});

      $user.fname = 'John';

      expect($user.is-dirty).to.be-truthy;
    }

    it 'saves successfully', {
      my $user = IdUser.create({fname => 'Fred'});
      $user.fname = 'John';

      expect($user.save).to.be-truthy;
    }

    it 'becomes clean after save', {
      my $user = IdUser.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;

      expect($user.is-dirty).to.be-falsy;
    }

    it 'persists the new value', {
      my $user = IdUser.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;

      expect($user.fname).to.eq('John');
    }
  }

  context 'a second record', {
    it 'is not dirty when freshly created', {
      IdUser.create({fname => 'Fred'});
      my $user2 = IdUser.create({fname => 'Bob'});

      expect($user2.is-dirty).to.be-falsy;
    }

    it 'becomes dirty after mutation', {
      IdUser.create({fname => 'Fred'});
      my $user2 = IdUser.create({fname => 'Bob'});

      $user2.fname = 'Jim';

      expect($user2.is-dirty).to.be-truthy;
    }

    it 'does not flip the first record dirty', {
      my $user = IdUser.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;
      my $user2 = IdUser.create({fname => 'Bob'});
      $user2.fname = 'Jim';

      expect($user.is-dirty).to.be-falsy;
    }
  }
}
