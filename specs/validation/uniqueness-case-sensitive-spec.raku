use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PhuserCI is Model {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => False } }
  }
}

class PhuserCS is Model {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => True } }
  }
}

class PhuserDefault is Model {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

describe 'uniqueness with case-sensitive option', {
  before-each { PhuserCI.destroy-all }
  after-each  { PhuserCI.destroy-all }

  context 'case-insensitive', {
    it 'allows the first record', {
      my $u = PhuserCI.create({username => 'Alfred'});
      expect($u.is-valid).to.be-truthy;
    }

    it 'rejects a different-case duplicate', {
      PhuserCI.create({username => 'Alfred'});
      my $clash = PhuserCI.build({username => 'alfred'});
      expect($clash.is-invalid).to.be-truthy;
    }

    it 'reports "must be unique"', {
      PhuserCI.create({username => 'Alfred'});
      my $clash = PhuserCI.build({username => 'alfred'});
      $clash.is-invalid;
      expect($clash.errors.username[0]).to.eq('must be unique');
    }
  }

  context 'case-sensitive => True', {
    it 'allows a different-case value', {
      PhuserCI.create({username => 'Alfred'});
      my $cs = PhuserCS.build({username => 'alfred'});
      expect($cs.is-valid).to.be-truthy;
    }
  }

  context 'default uniqueness', {
    it 'is case-sensitive (allows different case)', {
      PhuserCI.create({username => 'Alfred'});
      my $default = PhuserDefault.build({username => 'alfred'});
      expect($default.is-valid).to.be-truthy;
    }

    it 'still fails on an exact match', {
      PhuserCI.create({username => 'Alfred'});
      my $exact = PhuserDefault.build({username => 'Alfred'});
      expect($exact.is-invalid).to.be-truthy;
    }
  }
}
