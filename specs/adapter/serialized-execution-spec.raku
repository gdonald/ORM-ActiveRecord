use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

my $shared = DB.shared.adapter;
my $has-db = $shared.defined && $shared.is-connected;

my &group = $has-db ?? &describe !! &xdescribe;

# An adapter's connection is a single protocol stream, so the adapter
# serializes statement execution, transaction blocks, and lifecycle calls.
# Before the serial lock, concurrent statements on one connection desynced
# the wire protocol (libpq: "message type 0x.. arrived from server while
# idle") and every later call on that connection blocked forever.
group 'serialized execution on one adapter', :order<defined>, {
  it 'answers every statement correctly under a concurrent exec storm', {
    my @wrong = await (^16).map: -> $thread {
      start {
        my @misses;
        for ^20 {
          my $row = $shared.exec('SELECT 17')[0][0].Int;
          @misses.push($row) unless $row == 17;
        }
        @misses;
      }
    }
    expect(@wrong.map(*.elems).sum).to.eq(0);
  }

  it 'answers every read correctly while another thread recycles the connection', {
    my @readers = (^8).map: -> $thread {
      start {
        my @misses;
        for ^10 {
          my $row = $shared.exec('SELECT 23')[0][0].Int;
          @misses.push($row) unless $row == 23;
        }
        @misses;
      }
    }

    my $recycler = start { $shared.reconnect for ^5 };

    my @wrong = await @readers;
    await $recycler;

    expect(@wrong.map(*.elems).sum).to.eq(0);
  }

  context 'with a counter table', :order<defined>, {
    before-each {
      $shared.exec('DROP TABLE IF EXISTS serial_counters');
      $shared.exec('CREATE TABLE serial_counters (n INTEGER)');
      $shared.exec('INSERT INTO serial_counters (n) VALUES (0)');
    }
    after-each { $shared.exec('DROP TABLE IF EXISTS serial_counters') }

    it 'loses no update when transactions read-then-write concurrently', {
      await (^8).map: -> $thread {
        start {
          for ^5 {
            $shared.transaction({
              my $n = $shared.exec('SELECT n FROM serial_counters')[0][0].Int;
              $shared.exec("UPDATE serial_counters SET n = {$n + 1}");
            });
          }
        }
      }
      expect($shared.exec('SELECT n FROM serial_counters')[0][0].Int).to.eq(40);
    }

    it 'runs statements inside a nested transaction while holding the serial lock', {
      $shared.transaction({
        $shared.exec('UPDATE serial_counters SET n = 1');
        $shared.transaction({
          my $n = $shared.exec('SELECT n FROM serial_counters')[0][0].Int;
          $shared.exec("UPDATE serial_counters SET n = {$n + 1}");
        }, :requires-new);
      });
      expect($shared.exec('SELECT n FROM serial_counters')[0][0].Int).to.eq(2);
    }
  }
}
