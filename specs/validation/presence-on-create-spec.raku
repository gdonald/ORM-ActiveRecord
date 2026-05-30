use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::PresenceOnCreate;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'presence on: :create', {
  after-each { User.destroy-all }

  context 'create with no args', {
    it 'is invalid', {
      my $user = User.create();
      expect($user.is-invalid).to.be-truthy;
    }

    it 'reports "must be present"', {
      my $user = User.create();
      expect($user.errors.fname[0]).to.eq('must be present');
    }
  }

  context 'create with empty hash', {
    it 'is invalid', {
      my $user = User.create({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'reports "must be present"', {
      my $user = User.create({});
      expect($user.errors.fname[0]).to.eq('must be present');
    }
  }

  context 'create with fname', {
    it 'is valid', {
      my $user = User.create({fname => 'Greg'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'has no fname error', {
      my $user = User.create({fname => 'Greg'});
      expect($user.errors.fname[0]).to.be-falsy;
    }
  }

  context 'after update clearing fname', {
    it 'saves successfully', {
      my $user = User.create({fname => 'Greg'});
      $user.fname = Nil;
      expect($user.save).to.be-truthy;
    }

    it 'is valid (presence only fires on create)', {
      my $user = User.create({fname => 'Greg'});
      $user.fname = Nil;
      $user.save;
      expect($user.is-valid).to.be-truthy;
    }

    it 'has no fname error', {
      my $user = User.create({fname => 'Greg'});
      $user.fname = Nil;
      $user.save;
      expect($user.errors.fname[0]).to.be-falsy;
    }
  }
}
