use lib 'lib';
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
    it 'reconnects a connection that died while idle', {
      my $pool = new-pool(size => 1);
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
}
