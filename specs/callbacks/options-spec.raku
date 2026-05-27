use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my @events;

class OpClient is Model {
  method table-name { 'clients' }

  has Bool $.skip-it is rw = False;

  submethod BUILD {
    self.validate: 'email', { :presence };

    self.before-save: 'note-save';

    self.after-save: -> { @events.push: 'after-1' };
    self.after-save: -> { @events.push: 'after-2' };

    self.after-save: 'prepended-after', :prepend;

    self.after-save: -> { @events.push: 'maybe-block' }, :if(-> { self.email.chars > 3 });
    self.after-save: -> { @events.push: 'never-block' }, :unless(-> { True });

    self.after-save: -> { @events.push: 'should-skip' }, :if('skip-it');

    self.after-save: -> { @events.push: 'both-conds' },
      :if(['email-long', -> { True }]);

    self.before-update: -> { False };
  }

  method note-save             { @events.push: 'before-save-method'; True }
  method prepended-after       { @events.push: 'prepended-after-method' }
  method email-long(--> Bool)  { self.email.chars > 3 }
}

describe 'callback options', {
  before-each {
    OpClient.destroy-all;
  }

  after-each {
    OpClient.destroy-all;
  }

  context 'after creating a Client', {
    before-each {
      @events = ();
      OpClient.create({ email => 'fred@aol.com' });
    }

    it 'places prepended callback at the front of the after-save chain', {
      my @after-events = @events.grep({ $_ ne 'before-save-method' });

      expect(@after-events[0]).to.eq('prepended-after-method');
    }

    it 'runs the method-name before-save callback via method dispatch', {
      expect(@events.first('before-save-method').defined).to.be-truthy;
    }

    it 'fires multiple after-save callbacks in declaration order', {
      my @ordered = @events.grep({ $_ eq 'after-1' || $_ eq 'after-2' }).Array;

      expect(@ordered).to.eq(['after-1', 'after-2']);
    }

    it 'fires :if(Block) when the condition is true', {
      expect(@events.first('maybe-block').defined).to.be-truthy;
    }

    it 'suppresses :unless(Block) when the condition is true', {
      expect(@events.first('never-block').defined).to.be-falsy;
    }

    it 'suppresses :if(Str) when the method returns False', {
      expect(@events.first('should-skip').defined).to.be-falsy;
    }

    it 'fires :if(Array) when every condition is true', {
      expect(@events.first('both-conds').defined).to.be-truthy;
    }
  }

  context 'before-update returning False', {
    it 'halts save', {
      OpClient.create({ email => 'fred@aol.com' });
      my $c = OpClient.where({ email => 'fred@aol.com' }).first;
      $c.email = 'wilma@aol.com';

      expect($c.save).to.be-falsy;
    }
  }
}
