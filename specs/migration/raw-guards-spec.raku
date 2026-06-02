use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub cleanup-tables {
  try { $adapter.ddl-drop-table('_rg_safe') if table-exists('_rg_safe') }
}

# Captures everything a migration writes to $*OUT so the reporter helpers can
# be asserted without leaking to the real stdout behave parses.
class OutCapture {
  has Str @.lines;
  method say(|c)   { @!lines.push(c.list.join ~ "\n") }
  method print(|c) { @!lines.push(c.list.join) }
  method text(--> Str) { @!lines.join }
}

sub capture(&block --> Str) {
  my $cap = OutCapture.new;
  {
    my $*OUT = $cap;
    block();
  }
  $cap.text;
}

class NormalMig is Migration {
  method change { }
}

class NoTxnMig is Migration {
  method disable-ddl-transaction { True }
  method change { }
}

class SafetyMig is Migration {
  method change {
    self.safety-assured: -> {
      self.create-table: '_rg_safe', [ name => { :string, limit => 16 } ];
    };
  }
}

class AnnounceMig is Migration {
  method change { self.announce('doing the thing') }
}

class SayMig is Migration {
  method change {
    self.say('top level');
    self.say('nested', :subitem);
  }
}

class SuppressedMig is Migration {
  method change {
    self.suppress-messages: -> {
      self.announce('hidden banner');
      self.say('hidden line');
    };
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration raw SQL and guards', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'disable-ddl-transaction', :order<defined>, {
    it 'defaults to False', {
      expect(NormalMig.new.disable-ddl-transaction).to.be-falsy;
    }

    it 'can be overridden to True', {
      expect(NoTxnMig.new.disable-ddl-transaction).to.be-truthy;
    }

    context 'the runner honours the flag', :order<defined>, {
      it 'wraps a normal migration in a transaction', {
        expect(Migrate.new(:args([])).wraps-in-transaction(NormalMig.new)).to.be-truthy;
      }

      it 'skips the transaction when the migration opts out', {
        expect(Migrate.new(:args([])).wraps-in-transaction(NoTxnMig.new)).to.be-falsy;
      }
    }
  }

  context 'safety-assured', :order<defined>, {
    context 'on up', :order<defined>, {
      before-all { SafetyMig.new.up }

      it 'runs the wrapped DDL', {
        expect(table-exists('_rg_safe')).to.be-truthy;
      }
    }

    context 'on down (the wrapped DDL still inverts)', :order<defined>, {
      before-all { SafetyMig.new.down }

      it 'reverses the wrapped DDL', {
        expect(table-exists('_rg_safe')).to.be-falsy;
      }
    }
  }

  context 'announce', {
    it 'prints a banner containing the message', {
      expect(capture({ AnnounceMig.new.up }).contains('== doing the thing')).to.be-truthy;
    }
  }

  context 'say', {
    it 'prints a top-level line with a -- prefix', {
      expect(capture({ SayMig.new.up }).contains('-- top level')).to.be-truthy;
    }

    it 'indents a subitem with ->', {
      expect(capture({ SayMig.new.up }).contains('   -> nested')).to.be-truthy;
    }
  }

  context 'say-with-time', :order<defined>, {
    it 'reports the message', {
      expect(capture({ NormalMig.new.say-with-time('counting', -> { 5 }) }).contains('-- counting')).to.be-truthy;
    }

    it 'reports the elapsed time in seconds', {
      expect(capture({ NormalMig.new.say-with-time('counting', -> { 5 }) }).contains('s')).to.be-truthy;
    }

    it 'reports the row count when the block returns an Int', {
      expect(capture({ NormalMig.new.say-with-time('counting', -> { 5 }) }).contains('5 rows')).to.be-truthy;
    }

    it 'returns the block result', {
      my $r;
      capture({ $r = NormalMig.new.say-with-time('counting', -> { 42 }) });
      expect($r).to.eq(42);
    }
  }

  context 'suppress-messages', :order<defined>, {
    it 'silences announce and say output', {
      expect(capture({ SuppressedMig.new.up })).to.eq('');
    }

    it 'returns the block result', {
      my $r;
      capture({ $r = NormalMig.new.suppress-messages(-> { 99 }) });
      expect($r).to.eq(99);
    }
  }
}
