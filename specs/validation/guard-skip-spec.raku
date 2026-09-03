use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::GuardSkip;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'a validation whose :if guard is false', {
  after-each {
    GuardedContract.destroy-all;
    GuardedClient.destroy-all;
  }

  context 'acceptance', {
    it 'does not run when the guard is closed', {
      my $contract = GuardedContract.build({name => 'Unaccepted', terms => False});

      expect($contract.is-valid).to.be-truthy;
    }

    it 'records no error when the guard is closed', {
      my $contract = GuardedContract.build({name => 'Unaccepted', terms => False});
      $contract.is-invalid;

      expect($contract.errors.errors.elems).to.eq(0);
    }

    it 'still runs when the guard is open', {
      my $contract = OpenGuardContract.build({name => 'Unaccepted', terms => False});

      expect($contract.is-valid).to.be-falsy;
    }
  }

  context 'confirmation', {
    it 'does not run when the guard is closed', {
      my $client = GuardedClient.build({email => 'someone@example.com'});

      expect($client.is-valid).to.be-truthy;
    }

    it 'records no error when the guard is closed', {
      my $client = GuardedClient.build({email => 'someone@example.com'});
      $client.is-invalid;

      expect($client.errors.errors.elems).to.eq(0);
    }
  }
}
