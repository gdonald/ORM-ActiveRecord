use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Acceptance;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'acceptance validation', {
  after-each {
    Contract.destroy-all;
  }

  context 'when terms are not accepted', {
    it 'is invalid', {
      my $contract = Contract.create({name => 'Offical Document', terms => False});
      expect($contract.is-valid).to.be-falsy;
    }

    it 'reports a "must be accepted" error', {
      my $contract = Contract.create({name => 'Offical Document', terms => False});
      expect($contract.errors.terms[0]).to.eq('must be accepted');
    }
  }

  context 'when terms are accepted', {
    it 'is valid', {
      my $contract = Contract.create({name => 'Offical Document', terms => True});
      expect($contract.is-valid).to.be-truthy;
    }

    it 'records no errors on terms', {
      my $contract = Contract.create({name => 'Offical Document', terms => True});
      expect($contract.errors.terms).to.be-falsy;
    }
  }
}
