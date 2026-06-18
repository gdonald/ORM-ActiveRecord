use lib 'lib';
use BDD::Behave;
use JSON::Tiny;
use ORM::ActiveRecord::Support::Log;

describe 'structured logging', {
  my @captured;

  before-each {
    %*ENV<DISABLE-SQL-LOG>:delete;
    Log.reset;
    @captured = [];
    Log.set-sink(-> $line, $level { @captured.push: %( :$line, :$level ) });
  }

  after-each { Log.reset }

  sub last-line { @captured.tail<line> }

  context 'bound values', {
    before-each { Log.set-colour(False) }

    it 'includes the timing in the query log', {
      Log.query(sql => 'SELECT 1', ms => 5, binds => ['Ada']);
      expect(last-line.contains('(5ms)')).to.be-truthy;
    }

    it 'includes the bound values', {
      Log.query(sql => 'INSERT INTO users (name) VALUES (?)', ms => 5, binds => ['Ada']);
      expect(last-line.contains("[binds: 'Ada']")).to.be-truthy;
    }

    it 'renders numbers bare and undefined as NULL', {
      Log.query(sql => 'SELECT 1', ms => 1, binds => [7, Any]);
      expect(last-line.contains('7, NULL')).to.be-truthy;
    }
  }

  context 'colour toggle', {
    it 'emits ANSI escapes when colour is on', {
      Log.set-colour(True);
      Log.query(sql => 'SELECT 1', ms => 1);
      expect(last-line.contains("\e[")).to.be-truthy;
    }

    it 'emits plain text when colour is off', {
      Log.set-colour(False);
      Log.query(sql => 'SELECT 1', ms => 1);
      expect(last-line.contains("\e[")).to.be-falsy;
    }
  }

  context 'JSON formatter', {
    before-each { Log.set-format('json') }

    it 'tags the entry kind', {
      Log.query(sql => 'SELECT 1', ms => 3, binds => ['x']);
      expect(from-json(last-line)<kind>).to.eq('query');
    }

    it 'carries the binds', {
      Log.query(sql => 'SELECT 1', ms => 3, binds => ['x']);
      expect(from-json(last-line)<binds>[0]).to.eq('x');
    }
  }

  context 'level gating', {
    before-each { Log.set-level('warn') }

    it 'suppresses a normal query below the configured level', {
      Log.query(sql => 'SELECT 1', ms => 1, slow => False);
      expect(@captured.elems).to.eq(0);
    }

    it 'still logs a slow query at the warn level', {
      Log.query(sql => 'SELECT 1', ms => 9000, slow => True);
      expect(@captured.elems).to.eq(1);
    }
  }
}
