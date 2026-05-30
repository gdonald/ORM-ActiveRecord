use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::Options;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'callback options', {
  before-each {
    Client.destroy-all;
  }

  after-each {
    Client.destroy-all;
  }

  context 'after creating a Client', {
    before-each {
      @Callbacks::Options::events = ();
      Client.create({ email => 'fred@aol.com' });
    }

    it 'places prepended callback at the front of the after-save chain', {
      my @after-events = @Callbacks::Options::events.grep({ $_ ne 'before-save-method' });

      expect(@after-events[0]).to.eq('prepended-after-method');
    }

    it 'runs the method-name before-save callback via method dispatch', {
      expect(@Callbacks::Options::events.first('before-save-method').defined).to.be-truthy;
    }

    it 'fires multiple after-save callbacks in declaration order', {
      my @ordered = @Callbacks::Options::events.grep({ $_ eq 'after-1' || $_ eq 'after-2' }).Array;

      expect(@ordered).to.eq(['after-1', 'after-2']);
    }

    it 'fires :if(Block) when the condition is true', {
      expect(@Callbacks::Options::events.first('maybe-block').defined).to.be-truthy;
    }

    it 'suppresses :unless(Block) when the condition is true', {
      expect(@Callbacks::Options::events.first('never-block').defined).to.be-falsy;
    }

    it 'suppresses :if(Str) when the method returns False', {
      expect(@Callbacks::Options::events.first('should-skip').defined).to.be-falsy;
    }

    it 'fires :if(Array) when every condition is true', {
      expect(@Callbacks::Options::events.first('both-conds').defined).to.be-truthy;
    }
  }

  context 'before-update returning False', {
    it 'halts save', {
      Client.create({ email => 'fred@aol.com' });
      my $c = Client.where({ email => 'fred@aol.com' }).first;
      $c.email = 'wilma@aol.com';

      expect($c.save).to.be-falsy;
    }
  }
}
