use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class UnPerson is Model {
  method table-name { 'persons' }

  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

describe 'uniqueness validator', {
  before-each { UnPerson.destroy-all }
  after-each  { UnPerson.destroy-all }

  context 'first record', {
    it 'is valid', {
      my $person = UnPerson.create({username => 'alfred'});
      expect($person.is-valid).to.be-truthy;
    }

    it 'has no username error', {
      my $person = UnPerson.create({username => 'alfred'});
      expect($person.errors.username).to.be-falsy;
    }
  }

  context 'duplicate record', {
    it 'is invalid', {
      UnPerson.create({username => 'alfred'});
      my $dup = UnPerson.build({username => 'alfred'});
      expect($dup.is-invalid).to.be-truthy;
    }

    it 'reports "must be unique"', {
      UnPerson.create({username => 'alfred'});
      my $dup = UnPerson.build({username => 'alfred'});
      $dup.is-invalid;
      expect($dup.errors.username[0]).to.eq('must be unique');
    }
  }
}
