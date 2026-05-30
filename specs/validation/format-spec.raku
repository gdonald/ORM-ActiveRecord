use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Format;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-invalid = ['must be present', 'is invalid'];

describe 'format validator', {
  after-each { Contact.destroy-all }

  context 'missing email', {
    it 'is invalid', {
      my $contact = Contact.create({});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports a presence or invalid error', {
      my $contact = Contact.create({});
      expect(@presence-or-invalid.grep($contact.errors.email[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or invalid error', {
      my $contact = Contact.create({});
      expect(@presence-or-invalid.grep($contact.errors.email[1]).elems).to.be-greater-than(0);
    }
  }

  context 'malformed email', {
    it 'is invalid', {
      my $contact = Contact.create({email => 'foo'});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $contact = Contact.create({email => 'foo'});
      expect($contact.errors.email[0]).to.eq('is invalid');
    }
  }

  context 'well-formed email', {
    it 'is valid', {
      my $contact = Contact.create({email => 'foo@bar.com', fname => 'Gregory', lname => 'Donald'});
      expect($contact.is-valid).to.be-truthy;
    }

    it 'has no email error', {
      my $contact = Contact.create({email => 'foo@bar.com', fname => 'Gregory', lname => 'Donald'});
      expect($contact.errors.email).to.be-falsy;
    }
  }
}
