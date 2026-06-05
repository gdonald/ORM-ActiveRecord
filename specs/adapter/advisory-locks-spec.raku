use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $shared   = DB.shared.adapter;
my $has-db   = $shared.defined && $shared.is-connected;
my $supports = $has-db && $shared.supports-advisory-locks;

my &group       = $has-db ?? &describe !! &xdescribe;
my &supported   = $supports ?? &context !! &xcontext;
my &unsupported = $supports ?? &xcontext !! &context;

group 'advisory locks', :order<defined>, {
  context 'the toggle', :order<defined>, {
    it 'is enabled by default', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.advisory-locks).to.be-truthy;
    }

    it 'runs the block without locking when disabled', {
      my $conn = DB.shared.build-connection;
      $conn.advisory-locks = False;
      LEAVE $conn.disconnect;
      expect($conn.with-advisory-lock('ar-off', { 7 })).to.eq(7);
    }
  }

  supported 'on an adapter with advisory-lock support', :order<defined>, {
    it 'acquires the lock', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.get-advisory-lock('ar-rt')).to.be-truthy;
    }

    it 'releases the lock', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      $conn.get-advisory-lock('ar-rt2');
      expect($conn.release-advisory-lock('ar-rt2')).to.be-truthy;
    }

    it 'returns the block result from with-advisory-lock', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.with-advisory-lock('ar-res', { 99 })).to.eq(99);
    }

    it 'holds the lock against another connection during the block', {
      my $a = DB.shared.build-connection;
      my $b = DB.shared.build-connection;
      LEAVE { $a.disconnect; $b.disconnect }

      my $blocked;
      $a.with-advisory-lock('ar-hold', {
        $blocked = $b.get-advisory-lock('ar-hold', timeout => 0.2);
      });

      expect($blocked).to.be-falsy;
    }

    it 'frees the lock once the block exits', {
      my $a = DB.shared.build-connection;
      my $b = DB.shared.build-connection;
      LEAVE { $a.disconnect; $b.disconnect }

      $a.with-advisory-lock('ar-free', { ; });
      my $got = $b.get-advisory-lock('ar-free', timeout => 0.2);
      $b.release-advisory-lock('ar-free');

      expect($got).to.be-truthy;
    }

    it 'throws when it cannot acquire within the timeout', {
      my $a = DB.shared.build-connection;
      my $b = DB.shared.build-connection;
      LEAVE { $a.disconnect; $b.disconnect }

      $a.get-advisory-lock('ar-timeout');
      expect({ $b.with-advisory-lock('ar-timeout', { 1 }, timeout => 0.2) }).to.raise-error(X::AdvisoryLock);
    }
  }

  unsupported 'on an adapter without advisory-lock support', :order<defined>, {
    it 'reports no support', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.supports-advisory-locks).to.be-falsy;
    }

    it 'runs the block without locking', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.with-advisory-lock('ar-x', { 5 })).to.eq(5);
    }

    it 'reports that no lock was acquired', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.get-advisory-lock('ar-x')).to.be-falsy;
    }
  }
}
