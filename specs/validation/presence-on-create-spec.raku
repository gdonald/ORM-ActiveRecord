use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PocUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, on => { :create } }
  }
}

describe 'presence on: :create', {
  after-each { PocUser.destroy-all }

  context 'create with no args', {
    it 'is invalid', {
      my $user = PocUser.create();
      expect($user.is-invalid).to.be-truthy;
    }

    it 'reports "must be present"', {
      my $user = PocUser.create();
      expect($user.errors.fname[0]).to.eq('must be present');
    }
  }

  context 'create with empty hash', {
    it 'is invalid', {
      my $user = PocUser.create({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'reports "must be present"', {
      my $user = PocUser.create({});
      expect($user.errors.fname[0]).to.eq('must be present');
    }
  }

  context 'create with fname', {
    it 'is valid', {
      my $user = PocUser.create({fname => 'Greg'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'has no fname error', {
      my $user = PocUser.create({fname => 'Greg'});
      expect($user.errors.fname[0]).to.be-falsy;
    }
  }

  context 'after update clearing fname', {
    it 'saves successfully', {
      my $user = PocUser.create({fname => 'Greg'});
      $user.fname = Nil;
      expect($user.save).to.be-truthy;
    }

    it 'is valid (presence only fires on create)', {
      my $user = PocUser.create({fname => 'Greg'});
      $user.fname = Nil;
      $user.save;
      expect($user.is-valid).to.be-truthy;
    }

    it 'has no fname error', {
      my $user = PocUser.create({fname => 'Greg'});
      $user.fname = Nil;
      $user.save;
      expect($user.errors.fname[0]).to.be-falsy;
    }
  }
}
