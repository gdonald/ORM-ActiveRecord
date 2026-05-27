use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

class FakeHandle {
  has Str $.captured is rw = '';
  has Str @!lines;
  has Int $!pos = 0;

  submethod BUILD(Str :$reply = '') {
    @!lines = $reply.lines;
  }

  method get {
    return Str unless $!pos < @!lines.elems;
    @!lines[$!pos++];
  }

  method print(*@parts) {
    $!captured ~= @parts.map(*.Str).join;
    True;
  }

  method say(*@parts) {
    self.print(@parts);
    $!captured ~= "\n";
    True;
  }

  method flush() { True }
}

# Use an isolated SQLite :memory: DB so the canonical DB.shared schema
# is never touched. The shared singleton is swapped in before-each and
# restored in after-each.

my $original-shared;
my $iso-db;

sub install-iso-db() {
  $original-shared = DB.shared;
  $iso-db = DB.new(adapter => SqliteAdapter.new(database => ':memory:'));
  DB.set-shared($iso-db);
  $iso-db;
}

sub restore-shared() {
  DB.set-shared($original-shared) if $original-shared.defined;
  $original-shared = Nil;
  $iso-db = Nil;
}

sub seed-tables($db, *@names) {
  for @names -> $t {
    $db.ddl-create-table($t, [ name => { :string } ]);
  }
}

sub run-reset(:@args = [], Str :$reply = '') {
  my $io = FakeHandle.new(:$reply);
  my @dropped = Migrate.new(args => ()).reset(:@args, in => $io, out => $io);
  { out => $io.captured, dropped => @dropped.list };
}

describe 'Migrate.reset', {
  before-each { install-iso-db() }
  after-each  { restore-shared() }

  context 'pressing Enter (empty reply) confirms and drops all tables', {
    it 'drops all 3 tables', {
      seed-tables($iso-db, 'foos', 'bars', 'bazes');
      my %r = run-reset(reply => "\n");

      expect(%r<dropped>.elems).to.eq(3);
    }

    it 'every seeded table is dropped', {
      seed-tables($iso-db, 'foos', 'bars', 'bazes');
      my %r = run-reset(reply => "\n");

      expect(%r<dropped>.Set === <foos bars bazes>.Set).to.be-truthy;
    }

    it 'prompt mentions the action', {
      seed-tables($iso-db, 'foos', 'bars', 'bazes');
      my %r = run-reset(reply => "\n");

      expect(%r<out>.contains('About to DROP')).to.be-truthy;
    }

    it 'success message reports count', {
      seed-tables($iso-db, 'foos', 'bars', 'bazes');
      my %r = run-reset(reply => "\n");

      expect(%r<out>.contains('Dropped 3 tables')).to.be-truthy;
    }

    it 'database has zero tables after reset', {
      seed-tables($iso-db, 'foos', 'bars', 'bazes');
      run-reset(reply => "\n");

      expect($iso-db.get-table-names.elems).to.eq(0);
    }
  }

  context "'Y' confirms", {
    it 'drops the table', {
      seed-tables($iso-db, 'alpha');
      my %r = run-reset(reply => "Y\n");

      expect(%r<dropped>.elems).to.eq(1);
    }

    it 'cleared the table', {
      seed-tables($iso-db, 'alpha');
      run-reset(reply => "Y\n");

      expect($iso-db.get-table-names.elems).to.eq(0);
    }
  }

  it "'y' (lower-case) confirms", {
    seed-tables($iso-db, 'alpha');
    my %r = run-reset(reply => "y\n");

    expect(%r<dropped>.elems).to.eq(1);
  }

  context "'n' aborts", {
    it 'drops nothing', {
      seed-tables($iso-db, 'alpha', 'beta');
      my %r = run-reset(reply => "n\n");

      expect(%r<dropped>.elems).to.eq(0);
    }

    it 'prints the aborted message', {
      seed-tables($iso-db, 'alpha', 'beta');
      my %r = run-reset(reply => "n\n");

      expect(%r<out>.contains('Aborted')).to.be-truthy;
    }

    it 'preserves tables on abort', {
      seed-tables($iso-db, 'alpha', 'beta');
      run-reset(reply => "n\n");

      expect($iso-db.get-table-names.elems).to.eq(2);
    }
  }

  context 'any non-Y character aborts', {
    for <q maybe 0> -> $reply {
      it "reply '$reply' is treated as a refusal", {
        seed-tables($iso-db, 'alpha');
        my %r = run-reset(reply => "$reply\n");

        expect(%r<dropped>.elems).to.eq(0);
      }
    }
  }

  it 'leading whitespace before y is NOT treated as yes', {
    seed-tables($iso-db, 'alpha');
    my %r = run-reset(reply => " y\n");

    expect(%r<dropped>.elems).to.eq(0);
  }

  context '--yes flag bypasses the prompt', {
    it 'drops tables without consulting stdin', {
      seed-tables($iso-db, 'alpha', 'beta');
      my %r = run-reset(args => ['--yes'], reply => "n\n");

      expect(%r<dropped>.elems).to.eq(2);
    }

    it 'suppresses the prompt', {
      seed-tables($iso-db, 'alpha', 'beta');
      my %r = run-reset(args => ['--yes'], reply => "n\n");

      expect(%r<out>.contains('Proceed?')).to.be-falsy;
    }
  }

  it '-y short flag bypasses the prompt', {
    seed-tables($iso-db, 'alpha');
    my %r = run-reset(args => ['-y'], reply => "n\n");

    expect(%r<dropped>.elems).to.eq(1);
  }

  it 'AR_ASSUME_YES=1 env var bypasses the prompt', {
    seed-tables($iso-db, 'alpha');
    %*ENV<AR_ASSUME_YES> = '1';
    LEAVE %*ENV<AR_ASSUME_YES>:delete;
    my %r = run-reset(reply => "n\n");

    expect(%r<dropped>.elems).to.eq(1);
  }

  context 'empty database', {
    it 'has nothing to drop', {
      my %r = run-reset(reply => "y\n");

      expect(%r<dropped>.elems).to.eq(0);
    }

    it 'prints the no-op notice', {
      my %r = run-reset(reply => "y\n");

      expect(%r<out>.contains('Nothing to drop')).to.be-truthy;
    }
  }
}
