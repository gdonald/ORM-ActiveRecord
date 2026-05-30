use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Validation::UserFnameOnly;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'create + validation', {
  after-each { User.destroy-all }

  context 'User.create with no args', {
    it 'is invalid', {
      my $user = User.create;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.create;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.create;
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error', {
      my $user = User.create;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = User.create;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'User.create({}) with empty hash', {
    it 'is invalid', {
      my $user = User.create({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.create({});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.create({});
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error', {
      my $user = User.create({});
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = User.create({});
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'is invalid', {
      my $user = User.create({fname => 'x' x 33});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = User.create({fname => 'x' x 33});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = User.create({fname => 'x' x 33});
      expect($user.id).to.be-falsy;
    }

    it 'reports "only 32 characters allowed"', {
      my $user = User.create({fname => 'x' x 33});
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname', {
    it 'has a non-zero id', {
      my $user = User.create({fname => 'Greg'});
      expect($user.id).not.to.eq(0);
    }

    it 'is not invalid', {
      my $user = User.create({fname => 'Greg'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = User.create({fname => 'Greg'});
      expect($user.is-valid).to.be-truthy;
    }
  }
}
