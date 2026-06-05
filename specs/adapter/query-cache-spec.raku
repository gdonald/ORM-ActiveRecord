use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

my $shared = DB.shared.adapter;
my $has-db = $shared.defined && $shared.is-connected;

my &group = $has-db ?? &describe !! &xdescribe;

group 'query cache', :order<defined>, {
  context 'disabled by default', :order<defined>, {
    it 'reports the cache as disabled', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      expect($conn.query-cache-enabled).to.be-falsy;
    }

    it 'caches nothing while disabled', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      expect($conn.cached-query-count).to.eq(0);
    }
  }

  context 'enabled', :order<defined>, {
    it 'caches a read keyed by its sql', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      expect($conn.cached-query-count).to.eq(1);
    }

    it 'reuses the cached read for the same sql', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      $conn.exec('SELECT 1');
      expect($conn.cached-query-count).to.eq(1);
    }

    it 'caches distinct reads separately', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      $conn.exec('SELECT 2');
      expect($conn.cached-query-count).to.eq(2);
    }

    it 'returns the correct rows from a cached read', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      expect($conn.exec('SELECT 1')[0][0].Int).to.eq(1);
    }
  }

  context 'writes invalidate the cache', :order<defined>, {
    it 'clears the cache on a write', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('CREATE TEMPORARY TABLE qc_t (id INTEGER)');
      $conn.exec('SELECT id FROM qc_t');
      $conn.exec('INSERT INTO qc_t (id) VALUES (1)');
      expect($conn.cached-query-count).to.eq(0);
    }
  }

  context 'uncached', :order<defined>, {
    it 'bypasses the cache inside the block', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.uncached({ $conn.exec('SELECT 1') });
      expect($conn.cached-query-count).to.eq(0);
    }
  }

  context 'cache block', :order<defined>, {
    it 'enables the cache inside the block', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      my $inside;
      $conn.cache({ $inside = $conn.query-cache-enabled });
      expect($inside).to.be-truthy;
    }

    it 'restores the disabled state on exit', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      $conn.cache({ $conn.exec('SELECT 1') });
      expect($conn.query-cache-enabled).to.be-falsy;
    }

    it 'clears the cache on exit', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;
      $conn.cache({ $conn.exec('SELECT 1') });
      expect($conn.cached-query-count).to.eq(0);
    }
  }

  context 'disable-query-cache', :order<defined>, {
    it 'turns the cache off', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.disable-query-cache;
      expect($conn.query-cache-enabled).to.be-falsy;
    }

    it 'clears the cached reads', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      $conn.exec('SELECT 1');
      $conn.disable-query-cache;
      expect($conn.cached-query-count).to.eq(0);
    }
  }

  context 'DB-level helpers', :order<defined>, {
    it 'returns the block result from DB.cache', {
      expect(DB.shared.cache({ 42 })).to.eq(42);
    }

    it 'leaves the shared cache disabled after DB.cache', {
      DB.shared.cache({ DB.shared.adapter.exec('SELECT 1') });
      expect(DB.shared.query-cache-enabled).to.be-falsy;
    }
  }
}
