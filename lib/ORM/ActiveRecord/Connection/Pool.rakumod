
use ORM::ActiveRecord::Adapter;

# A bounded pool of database connections (each a fully-built Adapter with its
# own driver handle and transaction state). Connections are created lazily up
# to `size`, handed out by `checkout`, returned by `checkin`, and verified on
# checkout so a dropped connection is transparently reconnected.
#
#   my $pool = ConnectionPool.new(builder => { DB.shared.build-connection }, size => 5);
#   $pool.with-connection: -> $conn { $conn.exec('SELECT 1') };
class ConnectionPool is export {
  has &.builder is required;          # () --> a connected Adapter
  has Int  $.size = 5;                # max live connections
  has Int  $.min  = 0;                # pre-warmed idle connections
  has Real $.checkout-timeout = 5;    # seconds to wait for a free connection
  has Real $.verify-timeout   = 0;    # seconds for the checkout health probe (0 = unbounded)
  has Real $.idle-timeout     = 0;    # reap idle connections older than this (0 = never)
  has Real $.reaping-frequency = 0;   # advisory; reaping runs via `reap`

  has Lock $!lock = Lock.new;
  has      @!idle;                    # %( conn => Adapter, since => Instant )
  has      %!busy;                    # WHICH => Adapter
  has Int  $!created = 0;

  submethod TWEAK {
    self!warm if $!min > 0;
  }

  method !warm {
    $!lock.protect: {
      while $!created < min($!min, $!size) {
        @!idle.push: %( conn => &!builder(), since => now );
        $!created++;
      }
    }
  }

  method checkout(--> Adapter) {
    my $deadline = now + $!checkout-timeout;

    loop {
      my $conn = $!lock.protect: {
        if @!idle.elems {
          my %slot = @!idle.pop;
          %!busy{%slot<conn>.WHICH} = %slot<conn>;
          %slot<conn>;
        }
        elsif $!created < $!size {
          $!created++;
          my $c = &!builder();
          %!busy{$c.WHICH} = $c;
          $c;
        }
        else {
          Adapter;   # type object signals "none available"
        }
      };

      return self!ensure-live($conn) if $conn ~~ Adapter:D;

      die "ConnectionPool: checkout timed out after {$!checkout-timeout}s (pool size $!size)"
        if now > $deadline;

      sleep 0.005;
    }
  }

  method checkin($conn) {
    $!lock.protect: {
      %!busy{$conn.WHICH}:delete;
      @!idle.push: %( conn => $conn, since => now );
    }
  }

  method with-connection(&block) {
    my $conn = self.checkout;
    LEAVE self.checkin($conn);
    block($conn);
  }

  # Reconnect a connection that fails its health probe (driver-level drop).
  method !ensure-live($conn --> Adapter) {
    return $conn if self!alive($conn);
    $conn.reconnect;
    $conn;
  }

  method !alive($conn --> Bool) {
    return $conn.is-active unless $!verify-timeout > 0;

    my $probe = start { $conn.is-active };
    await Promise.anyof($probe, Promise.in($!verify-timeout));
    $probe.status == Kept ?? $probe.result !! False;
  }

  # Disconnect idle connections that have sat unused past `idle-timeout`,
  # keeping at least `min`.
  method reap {
    return unless $!idle-timeout > 0;
    my $cutoff = now - $!idle-timeout;

    $!lock.protect: {
      my @keep;
      for @!idle -> %slot {
        if %slot<since> < $cutoff && $!created > $!min {
          %slot<conn>.disconnect;
          $!created--;
        }
        else {
          @keep.push: %slot;
        }
      }
      @!idle = @keep;
    }
  }

  method disconnect-all {
    $!lock.protect: {
      .<conn>.disconnect for @!idle;
      .disconnect        for %!busy.values;
      @!idle    = ();
      %!busy    = ();
      $!created = 0;
    }
  }

  method stats(--> Hash) {
    $!lock.protect: {
      %( :$!size, created => $!created, idle => @!idle.elems, in-use => %!busy.elems );
    }
  }
}
