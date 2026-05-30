use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::UserPresenceLength;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'build (no save) validation', {
  after-each { User.destroy-all }

  context 'User.build with no attrs', {
    it 'is invalid', {
      my $user = User.build;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build;
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors from {presence,length}', {
      my $user = User.build;
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error from {presence,length}', {
      my $user = User.build;
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'User.build({}) with empty hash', {
    it 'is invalid', {
      my $user = User.build({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build({});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build({});
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors', {
      my $user = User.build({});
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = User.build({});
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'is invalid', {
      my $user = User.build({fname => 'x' x 33});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.build({fname => 'x' x 33});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.build({fname => 'x' x 33});
      expect($user.id).to.be-falsy;
    }

    it 'reports "only 32 characters allowed"', {
      my $user = User.build({fname => 'x' x 33});
      $user.is-invalid;
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname + lname', {
    it 'has no id (build does not save)', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      expect($user.id).to.be-falsy;
    }

    it 'is not invalid', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = User.build({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }
  }
}
