use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my @events;

class VaClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-validation: -> { @events.push: 'before' };
    self.after-validation:  -> { @events.push: 'after'  };
  }
}

describe 'validation callbacks', {
  before-each {
    VaClient.destroy-all;
    @events = ();
  }

  after-each {
    VaClient.destroy-all;
  }

  context 'on is-valid for a valid record', {
    it 'fires before-validation then after-validation', {
      my $c = VaClient.build({ email => 'fred@aol.com' });
      $c.is-valid;

      expect(@events).to.eq(['before', 'after']);
    }
  }

  context 'on is-invalid for an invalid record', {
    it 'reports invalid', {
      my $c = VaClient.build({ email => '' });

      expect($c.is-invalid).to.be-truthy;
    }

    it 'fires before-validation then after-validation even when invalid', {
      my $c = VaClient.build({ email => '' });
      $c.is-invalid;

      expect(@events).to.eq(['before', 'after']);
    }
  }

  context 'on create', {
    it 'records the new row', {
      my $c = VaClient.create({ email => 'wilma@aol.com' });

      expect($c.id).not.to.eq(0);
    }

    it 'fires the validation callbacks during save', {
      VaClient.create({ email => 'wilma@aol.com' });

      expect(@events.grep('before').elems >= 1 && @events.grep('after').elems >= 1).to.be-truthy;
    }
  }
}
