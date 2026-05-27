use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BdUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }
}

my @presence-or-length = ['at least 4 characters required', 'must be present'];

describe 'build (no save) validation', {
  after-each { BdUser.destroy-all }

  context 'BdUser.build with no attrs', {
    it 'is invalid', {
      my $user = BdUser.build;
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BdUser.build;
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BdUser.build;
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors from {presence,length}', {
      my $user = BdUser.build;
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error from {presence,length}', {
      my $user = BdUser.build;
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'BdUser.build({}) with empty hash', {
    it 'is invalid', {
      my $user = BdUser.build({});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BdUser.build({});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BdUser.build({});
      expect($user.id).to.be-falsy;
    }

    it 'reports fname errors', {
      my $user = BdUser.build({});
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second fname error', {
      my $user = BdUser.build({});
      $user.is-invalid;
      expect(@presence-or-length.grep($user.errors.fname[1]).elems).to.be-greater-than(0);
    }
  }

  context 'fname too long', {
    it 'is invalid', {
      my $user = BdUser.build({fname => 'x' x 33});
      expect($user.is-invalid).to.be-truthy;
    }

    it 'is not valid', {
      my $user = BdUser.build({fname => 'x' x 33});
      expect($user.is-valid).to.be-falsy;
    }

    it 'has no id', {
      my $user = BdUser.build({fname => 'x' x 33});
      expect($user.id).to.be-falsy;
    }

    it 'reports "only 32 characters allowed"', {
      my $user = BdUser.build({fname => 'x' x 33});
      $user.is-invalid;
      expect($user.errors.fname[0]).to.eq('only 32 characters allowed');
    }
  }

  context 'valid fname + lname', {
    it 'has no id (build does not save)', {
      my $user = BdUser.build({fname => 'Greg', lname => 'Donald'});
      expect($user.id).to.be-falsy;
    }

    it 'is not invalid', {
      my $user = BdUser.build({fname => 'Greg', lname => 'Donald'});
      expect($user.is-invalid).to.be-falsy;
    }

    it 'is valid', {
      my $user = BdUser.build({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }
  }
}
