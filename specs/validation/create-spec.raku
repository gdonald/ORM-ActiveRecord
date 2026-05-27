use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CrUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
  }
}

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'create + validation', {
  after-each { CrUser.destroy-all }

  context 'CrUser.create with no args', {
    it 'is invalid', {
      my $user = CrUser.create;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = CrUser.create;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = CrUser.create;
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error', {
      my $user = CrUser.create;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = CrUser.create;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'CrUser.create({}) with empty hash', {
    it 'is invalid', {
      my $user = CrUser.create({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = CrUser.create({});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = CrUser.create({});
      expect($user.id).to.be-falsy;
    }

    it 'reports a fname error', {
      my $user = CrUser.create({});
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = CrUser.create({});
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'is invalid', {
      my $user = CrUser.create({fname => 'x' x 33});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = CrUser.create({fname => 'x' x 33});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = CrUser.create({fname => 'x' x 33});
      expect($user.id).to.be-falsy;
    }

    it 'reports "only 32 characters allowed"', {
      my $user = CrUser.create({fname => 'x' x 33});
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname', {
    it 'has a non-zero id', {
      my $user = CrUser.create({fname => 'Greg'});
      expect($user.id).not.to.eq(0);
    }

    it 'is not invalid', {
      my $user = CrUser.create({fname => 'Greg'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = CrUser.create({fname => 'Greg'});
      expect($user.is-valid).to.be-truthy;
    }
  }
}
