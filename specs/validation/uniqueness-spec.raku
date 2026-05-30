use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Uniqueness;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'uniqueness validator', {
  before-each { Person.destroy-all }
  after-each  { Person.destroy-all }

  context 'first record', {
    it 'is valid', {
      my $person = Person.create({username => 'alfred'});
      expect($person.is-valid).to.be-truthy;
    }

    it 'has no username error', {
      my $person = Person.create({username => 'alfred'});
      expect($person.errors.username).to.be-falsy;
    }
  }

  context 'duplicate record', {
    it 'is invalid', {
      Person.create({username => 'alfred'});
      my $dup = Person.build({username => 'alfred'});
      expect($dup.is-invalid).to.be-truthy;
    }

    it 'reports "must be unique"', {
      Person.create({username => 'alfred'});
      my $dup = Person.build({username => 'alfred'});
      $dup.is-invalid;
      expect($dup.errors.username[0]).to.eq('must be unique');
    }
  }
}
