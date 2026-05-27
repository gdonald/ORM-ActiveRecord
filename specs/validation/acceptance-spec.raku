use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AcContract is Model {
  method table-name { 'contracts' }

  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 8, max => 64 } }
    self.validate: 'terms', { :acceptance }
  }
}

describe 'acceptance validation', {
  after-each {
    AcContract.destroy-all;
  }

  context 'when terms are not accepted', {
    it 'is invalid', {
      my $contract = AcContract.create({name => 'Offical Document', terms => False});
      expect($contract.is-valid).to.be-falsy;
    }

    it 'reports a "must be accepted" error', {
      my $contract = AcContract.create({name => 'Offical Document', terms => False});
      expect($contract.errors.terms[0]).to.eq('must be accepted');
    }
  }

  context 'when terms are accepted', {
    it 'is valid', {
      my $contract = AcContract.create({name => 'Offical Document', terms => True});
      expect($contract.is-valid).to.be-truthy;
    }

    it 'records no errors on terms', {
      my $contract = AcContract.create({name => 'Offical Document', terms => True});
      expect($contract.errors.terms).to.be-falsy;
    }
  }
}
