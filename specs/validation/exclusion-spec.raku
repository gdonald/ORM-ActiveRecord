use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class ExPerson is Model {
  method table-name { 'persons' }

  submethod BUILD {
    self.validate: 'username', { :presence, exclusion => { in => <admin superuser> } }
  }
}

my @presence-or-invalid = ['must be present', 'is invalid'];

describe 'exclusion validator', {
  before-each { ExPerson.destroy-all }
  after-each  { ExPerson.destroy-all }

  context 'missing username', {
    it 'is invalid', {
      my $person = ExPerson.build({});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports a presence or invalid error', {
      my $person = ExPerson.build({});
      $person.is-invalid;
      expect(@presence-or-invalid.grep($person.errors.username[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or invalid error', {
      my $person = ExPerson.build({});
      $person.is-invalid;
      expect(@presence-or-invalid.grep($person.errors.username[1]).elems).to.be-greater-than(0);
    }
  }

  context 'reserved username "admin"', {
    it 'is invalid', {
      my $person = ExPerson.build({username => 'admin'});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $person = ExPerson.build({username => 'admin'});
      $person.is-invalid;
      expect($person.errors.username[0]).to.eq('is invalid');
    }
  }

  context 'reserved username "superuser"', {
    it 'is invalid', {
      my $person = ExPerson.build({username => 'superuser'});
      expect($person.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $person = ExPerson.build({username => 'superuser'});
      $person.is-invalid;
      expect($person.errors.username[0]).to.eq('is invalid');
    }
  }

  context 'allowed username "alfred"', {
    it 'is valid', {
      my $person = ExPerson.create({username => 'alfred'});
      expect($person.is-valid).to.be-truthy;
    }

    it 'has no username error', {
      my $person = ExPerson.create({username => 'alfred'});
      $person.is-valid;
      expect($person.errors.username).to.be-falsy;
    }
  }
}
