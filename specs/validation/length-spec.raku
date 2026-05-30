use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::ContactLength;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'length validator', {
  after-each { Contact.destroy-all }

  context 'fname is exactly 7 + lname valid', {
    it 'is valid', {
      my $contact = Contact.build({fname => 'Gregory', lname => 'Donald'});
      expect($contact.is-valid).to.be-truthy;
    }
  }

  context 'no attrs at all', {
    it 'is invalid', {
      my $contact = Contact.build;
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = Contact.build;
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'empty hash', {
    it 'is invalid', {
      my $contact = Contact.build({});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = Contact.build({});
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'fname is 8 chars', {
    it 'is invalid', {
      my $contact = Contact.build({email => 'foo@bar.com', fname => 'x' x 8, lname => 'Donald'});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = Contact.build({email => 'foo@bar.com', fname => 'x' x 8, lname => 'Donald'});
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'lname is 3 chars (under range)', {
    it 'is invalid', {
      my $contact = Contact.build({email => 'foo@bar.com', fname => 'Gregory', lname => 'x' x 3});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "4 to 32 characters required"', {
      my $contact = Contact.build({email => 'foo@bar.com', fname => 'Gregory', lname => 'x' x 3});
      $contact.is-invalid;
      expect($contact.errors.lname[0]).to.eq('4 to 32 characters required');
    }
  }
}
