use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::UniquenessCaseSensitive;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'uniqueness with case-sensitive option', {
  before-each { Patron.destroy-all }
  after-each  { Patron.destroy-all }

  context 'case-insensitive', {
    it 'allows the first record', {
      my $u = Patron.create({username => 'Alfred'});
      expect($u.is-valid).to.be-truthy;
    }

    it 'rejects a different-case duplicate', {
      Patron.create({username => 'Alfred'});
      my $clash = Patron.build({username => 'alfred'});
      expect($clash.is-invalid).to.be-truthy;
    }

    it 'reports "must be unique"', {
      Patron.create({username => 'Alfred'});
      my $clash = Patron.build({username => 'alfred'});
      $clash.is-invalid;
      expect($clash.errors.username[0]).to.eq('must be unique');
    }
  }

  context 'case-sensitive => True', {
    it 'allows a different-case value', {
      Patron.create({username => 'Alfred'});
      my $cs = Subscriber.build({username => 'alfred'});
      expect($cs.is-valid).to.be-truthy;
    }
  }

  context 'default uniqueness', {
    it 'is case-sensitive (allows different case)', {
      Patron.create({username => 'Alfred'});
      my $default = Visitor.build({username => 'alfred'});
      expect($default.is-valid).to.be-truthy;
    }

    it 'still fails on an exact match', {
      Patron.create({username => 'Alfred'});
      my $exact = Visitor.build({username => 'Alfred'});
      expect($exact.is-invalid).to.be-truthy;
    }
  }
}
