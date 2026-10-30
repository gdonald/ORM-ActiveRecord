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

  context 'updating a saved record', {
    let(:alfred, { Person.create({username => 'alfred'}) });

    context 'to a username another row has', {
      before-each { Person.create({username => 'bruce'}) }

      it 'is refused', {
        expect(alfred.update({username => 'bruce'})).to.be-falsy;
      }

      it 'records a taken error', {
        alfred.update({username => 'bruce'});
        expect(alfred.errors.is-of-kind('username', 'taken')).to.be-truthy;
      }
    }

    context 'keeping its own username', {
      it 'is accepted', {
        expect(alfred.update({username => 'alfred'})).to.be-truthy;
      }
    }
  }
}
