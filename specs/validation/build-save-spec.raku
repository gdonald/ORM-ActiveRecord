use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BsUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }
}

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'build + save validation', {
  after-each { BsUser.destroy-all }

  context 'BsUser.build with no attrs', {
    it 'does not save', {
      my $user = BsUser.build;
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = BsUser.build;
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BsUser.build;
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BsUser.build;
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error from {presence,length}', {
      my $user = BsUser.build;
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error from {presence,length}', {
      my $user = BsUser.build;
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'BsUser.build({}) with empty hash', {
    it 'does not save', {
      my $user = BsUser.build({});
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = BsUser.build({});
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BsUser.build({});
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BsUser.build({});
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors', {
      my $user = BsUser.build({});
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = BsUser.build({});
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'does not save', {
      my $user = BsUser.build({fname => 'x' x 33});
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = BsUser.build({fname => 'x' x 33});
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BsUser.build({fname => 'x' x 33});
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BsUser.build({fname => 'x' x 33});
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports an "only 32 characters allowed" error', {
      my $user = BsUser.build({fname => 'x' x 33});
      $user.save;
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname + lname', {
    it 'saves successfully', {
      my $user = BsUser.build({fname => 'Greg', lname => 'Donald'});
      expect($user.save).to.be-truthy;
    }

    it 'assigns a non-zero id', {
      my $user = BsUser.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.id).not.to.eq(0);
    }

    it 'is not invalid', {
      my $user = BsUser.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = BsUser.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.is-valid).to.be-truthy;
    }
  }
}
