use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class LeContact is Model {
  method table-name { 'contacts' }

  submethod BUILD {
    self.validate: 'fname', { length => { is => 7 } }
    self.validate: 'lname', { length => { in => 4..32 } }
  }
}

describe 'length validator', {
  after-each { LeContact.destroy-all }

  context 'fname is exactly 7 + lname valid', {
    it 'is valid', {
      my $contact = LeContact.build({fname => 'Gregory', lname => 'Donald'});
      expect($contact.is-valid).to.be-truthy;
    }
  }

  context 'no attrs at all', {
    it 'is invalid', {
      my $contact = LeContact.build;
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = LeContact.build;
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'empty hash', {
    it 'is invalid', {
      my $contact = LeContact.build({});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = LeContact.build({});
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'fname is 8 chars', {
    it 'is invalid', {
      my $contact = LeContact.build({email => 'foo@bar.com', fname => 'x' x 8, lname => 'Donald'});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "exactly 7 characters required"', {
      my $contact = LeContact.build({email => 'foo@bar.com', fname => 'x' x 8, lname => 'Donald'});
      $contact.is-invalid;
      expect($contact.errors.fname[0]).to.eq('exactly 7 characters required');
    }
  }

  context 'lname is 3 chars (under range)', {
    it 'is invalid', {
      my $contact = LeContact.build({email => 'foo@bar.com', fname => 'Gregory', lname => 'x' x 3});
      expect($contact.is-invalid).to.be-truthy;
    }

    it 'reports "4 to 32 characters required"', {
      my $contact = LeContact.build({email => 'foo@bar.com', fname => 'Gregory', lname => 'x' x 3});
      $contact.is-invalid;
      expect($contact.errors.lname[0]).to.eq('4 to 32 characters required');
    }
  }
}
