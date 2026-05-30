use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Exclusion;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-invalid = ['must be present', 'is invalid'];

describe 'exclusion validator', {
  before-each { Person.destroy-all }
  after-each  { Person.destroy-all }

  context 'missing username', {
    it 'is invalid', {
      my $person = Person.build({});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports a presence or invalid error', {
      my $person = Person.build({});
      $person.is-invalid;
      expect(@presence-or-invalid.grep($person.errors.username[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or invalid error', {
      my $person = Person.build({});
      $person.is-invalid;
      expect(@presence-or-invalid.grep($person.errors.username[1]).elems).to.be-greater-than(0);
    }
  }

  context 'reserved username "admin"', {
    it 'is invalid', {
      my $person = Person.build({username => 'admin'});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $person = Person.build({username => 'admin'});
      $person.is-invalid;
      expect($person.errors.username[0]).to.eq('is invalid');
    }
  }

  context 'reserved username "superuser"', {
    it 'is invalid', {
      my $person = Person.build({username => 'superuser'});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $person = Person.build({username => 'superuser'});
      $person.is-invalid;
      expect($person.errors.username[0]).to.eq('is invalid');
    }
  }

  context 'allowed username "alfred"', {
    it 'is valid', {
      my $person = Person.create({username => 'alfred'});
      expect($person.is-valid).to.be-truthy;
    }

    it 'has no username error', {
      my $person = Person.create({username => 'alfred'});
      $person.is-valid;
      expect($person.errors.username).to.be-falsy;
    }
  }
}
