use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my @events;

class SstClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-save: -> { @events.push: 'b1' }, :tag<b1>;
    self.before-save: -> { @events.push: 'b2' }, :tag<b2>;
    self.before-save: -> { @events.push: 'b3' }, :tag<b3>;
  }
}

describe 'callback introspection, skip, set, and terminator', {
  before-each {
    SstClient.destroy-all;
    @events = ();
  }

  after-each {
    SstClient.destroy-all;
  }

  context 'introspection', {
    it 'callbacks-for returns all registered callbacks', {
      my $c = SstClient.build({ email => 'fred@aol.com' });

      expect($c.callbacks-for(:event<save>, :timing<before>).elems).to.eq(3);
    }

    it 'callback-tags returns registered tags in order', {
      my $c = SstClient.build({ email => 'fred@aol.com' });

      expect($c.callback-tags(:event<save>, :timing<before>).Array).to.eq(['b1', 'b2', 'b3']);
    }

    it 'has-callback finds an entry by tag', {
      my $c = SstClient.build({ email => 'fred@aol.com' });

      expect($c.has-callback(:event<save>, :timing<before>, :tag<b2>)).to.be-truthy;
    }
  }

  context 'skip-callback', {
    it 'removes the entry by tag', {
      my $c = SstClient.build({ email => 'wilma@aol.com' });
      $c.skip-callback(:event<save>, :timing<before>, :tag<b2>);
      $c.save;

      expect(@events).to.eq(['b1', 'b3']);
    }
  }

  context 'set-callback', {
    it 'appends a new entry at runtime', {
      my $c = SstClient.build({ email => 'pebbles@aol.com' });
      $c.set-callback(
        :event<save>, :timing<before>,
        :handler(-> { @events.push: 'b4' }),
        :tag<b4>,
      );
      $c.save;

      expect(@events.tail).to.eq('b4');
    }
  }

  context 'X::Callback::Abort', {
    before-each {
      @events = ();
    }

    it 'halts save when thrown', {
      my $c = SstClient.build({ email => 'bambam@aol.com' });
      $c.set-callback(
        :event<save>, :timing<before>,
        :handler(-> { die X::Callback::Abort.new(:event<save>, :timing<before>) }),
        :prepend,
      );

      expect($c.save).to.be-falsy;
    }

    it 'stops further before-save callbacks from running', {
      my $c = SstClient.build({ email => 'bambam@aol.com' });
      $c.set-callback(
        :event<save>, :timing<before>,
        :handler(-> { die X::Callback::Abort.new(:event<save>, :timing<before>) }),
        :prepend,
      );
      $c.save;

      expect(@events.elems).to.eq(0);
    }
  }

  context 'custom terminator', {
    it 'halts the chain on a 0 return when set to treat 0 as abort', {
      my $c = SstClient.build({ email => 'dino@aol.com' });
      $c.set-callback-terminator(
        :event<save>, :timing<before>,
        :block(-> $r { $r === 0 }),
      );
      $c.skip-callback(:event<save>, :timing<before>, :tag<b1>);
      $c.skip-callback(:event<save>, :timing<before>, :tag<b2>);
      $c.skip-callback(:event<save>, :timing<before>, :tag<b3>);
      $c.set-callback(
        :event<save>, :timing<before>,
        :handler(-> { 0 }),
      );
      $c.set-callback(
        :event<save>, :timing<before>,
        :handler(-> { @events.push: 'after-zero' }),
      );
      $c.save;

      expect(@events.elems).to.eq(0);
    }
  }
}
