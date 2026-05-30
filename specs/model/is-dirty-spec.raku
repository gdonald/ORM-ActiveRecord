use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'is-dirty', {
  after-each {
    User.destroy-all;
  }

  context 'a freshly created record', {
    it 'is not dirty', {
      my $user = User.create({fname => 'Fred'});

      expect($user.is-dirty).to.be-falsy;
    }
  }

  context 'after mutating an attribute', {
    it 'becomes dirty', {
      my $user = User.create({fname => 'Fred'});

      $user.fname = 'John';

      expect($user.is-dirty).to.be-truthy;
    }

    it 'saves successfully', {
      my $user = User.create({fname => 'Fred'});
      $user.fname = 'John';

      expect($user.save).to.be-truthy;
    }

    it 'becomes clean after save', {
      my $user = User.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;

      expect($user.is-dirty).to.be-falsy;
    }

    it 'persists the new value', {
      my $user = User.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;

      expect($user.fname).to.eq('John');
    }
  }

  context 'a second record', {
    it 'is not dirty when freshly created', {
      User.create({fname => 'Fred'});
      my $user2 = User.create({fname => 'Bob'});

      expect($user2.is-dirty).to.be-falsy;
    }

    it 'becomes dirty after mutation', {
      User.create({fname => 'Fred'});
      my $user2 = User.create({fname => 'Bob'});

      $user2.fname = 'Jim';

      expect($user2.is-dirty).to.be-truthy;
    }

    it 'does not flip the first record dirty', {
      my $user = User.create({fname => 'Fred'});
      $user.fname = 'John';
      $user.save;
      my $user2 = User.create({fname => 'Bob'});
      $user2.fname = 'Jim';

      expect($user.is-dirty).to.be-falsy;
    }
  }
}
