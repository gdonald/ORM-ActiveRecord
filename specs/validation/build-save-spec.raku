use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::UserPresenceLength;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'build + save validation', {
  after-each { User.destroy-all }

  context 'User.build with no attrs', {
    it 'does not save', {
      my $user = User.build;
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = User.build;
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build;
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build;
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error from {presence,length}', {
      my $user = User.build;
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error from {presence,length}', {
      my $user = User.build;
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'User.build({}) with empty hash', {
    it 'does not save', {
      my $user = User.build({});
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = User.build({});
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build({});
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build({});
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors', {
      my $user = User.build({});
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = User.build({});
      $user.save;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'does not save', {
      my $user = User.build({fname => 'x' x 33});
      expect($user.save).to.be-falsy;
    }

    it 'is invalid', {
      my $user = User.build({fname => 'x' x 33});
      $user.save;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build({fname => 'x' x 33});
      $user.save;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build({fname => 'x' x 33});
      $user.save;
      expect($user.id).to.be-falsy;
    }

    it 'reports an "only 32 characters allowed" error', {
      my $user = User.build({fname => 'x' x 33});
      $user.save;
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname + lname', {
    it 'saves successfully', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      expect($user.save).to.be-truthy;
    }

    it 'assigns a non-zero id', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.id).not.to.eq(0);
    }

    it 'is not invalid', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      $user.save;
      expect($user.is-valid).to.be-truthy;
    }
  }
}
