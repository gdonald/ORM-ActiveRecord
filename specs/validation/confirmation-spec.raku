use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CfClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence, :confirmation }
  }
}

my @presence-or-confirmation = ['must be present', 'must be confirmed'];

describe 'confirmation validator', {
  after-each { CfClient.destroy-all }

  context 'no email at all', {
    it 'is invalid', {
      my $client = CfClient.build({});
      expect($client.is-invalid).to.be-truthy;
    }

    it 'reports a presence or confirmation error first', {
      my $client = CfClient.build({});
      $client.is-invalid;
      expect(@presence-or-confirmation.grep($client.errors.email[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or confirmation error', {
      my $client = CfClient.build({});
      $client.is-invalid;
      expect(@presence-or-confirmation.grep($client.errors.email[1]).elems).to.be-greater-than(0);
    }
  }

  context 'email without email_confirmation', {
    it 'is invalid', {
      my $client = CfClient.build({email => 'fred@aol.com'});
      expect($client.is-invalid).to.be-truthy;
    }

    it 'reports "must be confirmed"', {
      my $client = CfClient.build({email => 'fred@aol.com'});
      $client.is-invalid;
      expect($client.errors.email[0]).to.eq('must be confirmed');
    }
  }

  context 'matching email_confirmation', {
    it 'is valid', {
      my $client = CfClient.build({email => 'fred@aol.com', email_confirmation => 'fred@aol.com'});
      expect($client.is-valid).to.be-truthy;
    }

    it 'has no email error', {
      my $client = CfClient.build({email => 'fred@aol.com', email_confirmation => 'fred@aol.com'});
      $client.is-valid;
      expect($client.errors.email).to.be-falsy;
    }
  }
}
