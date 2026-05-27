use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class UpUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
  }
}

my @presence-or-length = ['must be present', 'at least 4 characters required'];

describe 'update with validation', {
  after-each { UpUser.destroy-all }

  context 'create with valid fname', {
    it 'gets a non-zero id', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.id).not.to.eq(0);
    }

    it 'is not invalid', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.is-valid).to.be-truthy;
    }
  }

  context 'update to a valid new fname', {
    it 'returns truthy', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.update({fname => 'Greg'})).to.be-truthy;
    }

    it 'is not invalid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'Greg'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'Greg'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'reflects the new fname', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'Greg'});
      expect($user.fname).to.eq('Greg');
    }
  }

  context 'update to too-short fname', {
    it 'returns falsy', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.update({fname => 'x'})).to.be-falsy;
    }

    it 'is invalid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x'});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x'});
      expect($user.is-valid).to.be-falsy;
    }

    it 'reports "at least 4 characters required"', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x'});
      expect($user.errors.fname[0]).to.eq('at least 4 characters required');
    }
  }

  context 'update to Nil fname', {
    it 'returns falsy', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.update({fname => Nil})).to.be-falsy;
    }

    it 'is invalid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => Nil});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => Nil});
      expect($user.is-valid).to.be-falsy;
    }

    it 'reports a presence or length error', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => Nil});
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or length error', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => Nil});
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'update to too-long fname', {
    it 'returns falsy', {
      my $user = UpUser.create({fname => 'Fred'});
      expect($user.update({fname => 'x' x 33})).to.be-falsy;
    }

    it 'is invalid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x' x 33});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x' x 33});
      expect($user.is-valid).to.be-falsy;
    }

    it 'reports "only 32 characters allowed"', {
      my $user = UpUser.create({fname => 'Fred'});
      $user.update({fname => 'x' x 33});
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }
}
