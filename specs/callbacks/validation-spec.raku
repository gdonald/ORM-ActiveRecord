use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::Validation;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'validation callbacks', {
  before-each {
    Client.destroy-all;
    @Callbacks::Validation::events = ();
  }

  after-each {
    Client.destroy-all;
  }

  context 'on is-valid for a valid record', {
    it 'fires before-validation then after-validation', {
      my $c = Client.build({ email => 'fred@aol.com' });
      $c.is-valid;

      expect(@Callbacks::Validation::events).to.eq(['before', 'after']);
    }
  }

  context 'on is-invalid for an invalid record', {
    it 'reports invalid', {
      my $c = Client.build({ email => '' });

      expect($c.is-invalid).to.be-truthy;
    }

    it 'fires before-validation then after-validation even when invalid', {
      my $c = Client.build({ email => '' });
      $c.is-invalid;

      expect(@Callbacks::Validation::events).to.eq(['before', 'after']);
    }
  }

  context 'on create', {
    it 'records the new row', {
      my $c = Client.create({ email => 'wilma@aol.com' });

      expect($c.id).not.to.eq(0);
    }

    it 'fires the validation callbacks during save', {
      Client.create({ email => 'wilma@aol.com' });

      expect(@Callbacks::Validation::events.grep('before').elems >= 1 && @Callbacks::Validation::events.grep('after').elems >= 1).to.be-truthy;
    }
  }
}
