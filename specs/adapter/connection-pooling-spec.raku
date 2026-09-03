use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Connection::Pool;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub new-pool(*%opts --> ConnectionPool) {
  ConnectionPool.new(builder => { DB.shared.build-connection }, |%opts);
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'connection pooling', :order<defined>, {
  context 'adapter health probes', :order<defined>, {
    it 'is-active is true on a live connection', {
      expect(DB.shared.is-active).to.be-truthy;
    }

    it 'verify reconnects a connection that has been disconnected', {
      my $c = DB.shared.build-connection;
      $c.disconnect;
      my $ok = $c.verify;
      $c.disconnect;
      expect($ok).to.be-truthy;
    }
  }

  context 'checkout / checkin', :order<defined>, {
    it 'checks out a live connection', {
      my $pool = new-pool(size => 2);
      my $conn = $pool.checkout;
      my $live = $conn.is-active;
      $pool.disconnect-all;
      expect($live).to.be-truthy;
    }

    it 'returns the connection to the pool on checkin', {
      my $pool = new-pool(size => 2);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      my %s = $pool.stats;
      $pool.disconnect-all;
      expect(%s<in-use>).to.eq(0);
    }

    it 'reuses an idle connection rather than growing the pool', {
      my $pool = new-pool(size => 5);
      $pool.checkin($pool.checkout);
      $pool.checkin($pool.checkout);
      my %s = $pool.stats;
      $pool.disconnect-all;
      expect(%s<created>).to.eq(1);
    }
  }

  context 'with-connection', :order<defined>, {
    it 'yields a connection and returns the block result', {
      my $pool = new-pool(size => 2);
      my $v = $pool.with-connection(-> $c { $c.exec('SELECT 1'); 42 });
      $pool.disconnect-all;
      expect($v).to.eq(42);
    }

    it 'checks the connection back in after the block', {
      my $pool = new-pool(size => 2);
      $pool.with-connection(-> $c { $c.exec('SELECT 1') });
      my %s = $pool.stats;
      $pool.disconnect-all;
      expect(%s<in-use>).to.eq(0);
    }
  }

  context 'size cap and checkout timeout', :order<defined>, {
    it 'throws when no connection frees up within the timeout', {
      my $pool = new-pool(size => 1, checkout-timeout => 0.2);
      my $held = $pool.checkout;
      my $second = try { $pool.checkout };
      $pool.disconnect-all;
      expect($second.defined).to.be-falsy;
    }
  }

  context 'auto-reconnect on a dropped connection', :order<defined>, {
    it 'reconnects a connection that died while idle when it probes on checkout', {
      my $pool = new-pool(size => 1, verify-idle-after => 0);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      $conn.disconnect;                 # simulate a driver-level drop
      my $again = $pool.checkout;       # checkout verifies and reconnects
      my $live = $again.is-active;
      $pool.disconnect-all;
      expect($live).to.be-truthy;
    }
  }

  context 'reaping idle connections', :order<defined>, {
    it 'disconnects connections idle past the idle timeout', {
      my $pool = new-pool(size => 2, idle-timeout => 0.01);
      $pool.checkin($pool.checkout);
      sleep 0.05;
      $pool.reap;
      my %s = $pool.stats;
      $pool.disconnect-all;
      expect(%s<created>).to.eq(0);
    }
  }

  context 'DB.with-connection', :order<defined>, {
    it 'runs a query on a pooled connection', {
      my @rows = DB.shared.with-connection(-> $c { $c.exec('SELECT 1') });
      DB.shared.pool.disconnect-all;
      expect(@rows[0][0].Int).to.eq(1);
    }
  }

  # Building a connection is a TCP connect and an auth handshake. Holding the
  # pool lock across it would block every other checkout and checkin, so the
  # slot is claimed under the lock and the connection built outside it.
  context 'building a connection', :order<defined>, {
    it 'does not hold the lock while the builder runs', {
      my $pool;
      my $seen-from-another-thread;

      $pool = ConnectionPool.new(
        size    => 2,
        builder => {
          # `stats` takes the pool lock. Reading it from another thread while
          # the builder runs only completes if the lock is free; the bound
          # turns a regression into a failure rather than a hang.
          my $probe = start { $pool.stats<created> };
          await Promise.anyof($probe, Promise.in(2));
          $seen-from-another-thread = $probe.status == Kept ?? $probe.result !! Nil;
          DB.shared.build-connection;
        },
      );

      $pool.checkout;
      $pool.disconnect-all;

      expect($seen-from-another-thread).to.eq(1);
    }

    it 'releases the claimed slot when the builder throws', {
      my $pool = ConnectionPool.new(size => 1, builder => { die 'no connection' });

      try $pool.checkout;

      expect($pool.stats<created>).to.eq(0);
    }

    it 'lets a later checkout try again after a failed build', {
      my $fail = True;
      my $pool = ConnectionPool.new(
        size    => 1,
        builder => { $fail ?? die 'no connection' !! DB.shared.build-connection },
      );

      try $pool.checkout;
      $fail = False;
      my $conn = $pool.checkout;
      LEAVE $pool.disconnect-all;

      expect($conn.defined).to.be-truthy;
    }
  }

  context 'waiting for a free connection', :order<defined>, {
    it 'hands the connection to a waiting checkout once it is returned', {
      my $pool = new-pool(size => 1, checkout-timeout => 5);
      my $held = $pool.checkout;

      my $waiting = start { $pool.checkout };
      $pool.checkin($held);

      my $got = await $waiting;
      $pool.disconnect-all;

      expect($got.defined).to.be-truthy;
    }

    it 'still times out when nothing is returned', {
      my $pool = new-pool(size => 1, checkout-timeout => 0.2);
      my $held = $pool.checkout;

      my $second = try { $pool.checkout };
      $pool.disconnect-all;

      expect($second.defined).to.be-falsy;
    }
  }

  context 'verify-idle-after', :order<defined>, {
    my role ProbeCounter {
      has Int $.probes is rw = 0;
      method is-active(--> Bool) { $!probes++; callsame }
    }

    my sub counting-pool(*%opts --> ConnectionPool) {
      ConnectionPool.new(builder => { DB.shared.build-connection does ProbeCounter }, |%opts);
    }

    it 'checks a recently used connection out without a probe by default', {
      my $pool = counting-pool(size => 1);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      $pool.checkout;
      $pool.disconnect-all;
      expect($conn.probes).to.eq(0);
    }

    it 'probes on every checkout when the threshold is set to zero', {
      my $pool = counting-pool(size => 1, verify-idle-after => 0);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      $pool.checkout;
      $pool.disconnect-all;
      expect($conn.probes).to.eq(2);
    }

    it 'checks out a connection idle less than the threshold without a probe', {
      my $pool = counting-pool(size => 1, verify-idle-after => 60);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      $pool.checkout;
      $pool.disconnect-all;
      expect($conn.probes).to.eq(0);
    }

    it 'probes a connection idle past the threshold on checkout', {
      my $pool = counting-pool(size => 1, verify-idle-after => 0.01);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      sleep 0.05;
      $pool.checkout;
      $pool.disconnect-all;
      expect($conn.probes).to.eq(1);
    }

    it 'recovers a read on a connection handed out without a probe', {
      my $pool = new-pool(size => 1);
      my $conn = $pool.checkout;
      $pool.checkin($conn);
      $conn.disconnect;
      my $again = $pool.checkout;
      my @rows = $again.exec('SELECT 1');
      $pool.disconnect-all;
      expect(@rows[0][0].Int).to.eq(1);
    }
  }
}
