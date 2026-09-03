use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Instrumentation::QueryLogs;
use ORM::ActiveRecord::Instrumentation::Notifications;

%*ENV<DISABLE-SQL-LOG> = True;

my $shared  = DB.shared.adapter;
my $has-db  = $shared.defined && $shared.is-connected;

sub adapter-kind(--> Str) {
  return 'none' without $shared;
  given $shared.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}
my $is-pg = adapter-kind() eq 'pg';

my &group = $has-db ?? &describe !! &xdescribe;

group 'prepared statement caching', :order<defined>, {
  context 'caching disabled (the default)', :order<defined>, {
    it 'does not cache statements', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');
      $conn.exec('SELECT 1');

      expect($conn.cached-statement-count).to.eq(0);
    }

    it 'still returns correct rows', {
      my $conn = DB.shared.build-connection;
      LEAVE $conn.disconnect;

      expect($conn.exec('SELECT 1')[0][0].Int).to.eq(1);
    }
  }

  # A query-log comment carries the controller and action, so it varies from one
  # request to the next and every execution is a fresh SQL text. Caching those
  # would fill the cache with entries nothing hits and evict the ones that are.
  context 'a statement carrying a query-log comment', :order<defined>, {
    let(:tagged-connection, {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      $conn;
    });

    before-each {
      QueryLogs.enable;
      QueryLogs.set-tags([ controller => 'orders' ]);
    }

    after-each { QueryLogs.reset }

    it 'is not cached', {
      LEAVE tagged-connection.disconnect;

      tagged-connection.exec('SELECT 1');
      tagged-connection.exec('SELECT 1');

      expect(tagged-connection.cached-statement-count).to.eq(0);
    }

    it 'still returns correct rows', {
      LEAVE tagged-connection.disconnect;

      expect(tagged-connection.exec('SELECT 1')[0][0].Int).to.eq(1);
    }

    it 'caches again once tagging is off', {
      LEAVE tagged-connection.disconnect;
      QueryLogs.reset;

      tagged-connection.exec('SELECT 1');
      tagged-connection.exec('SELECT 1');

      expect(tagged-connection.cached-statement-count).to.eq(1);
    }

    it 'still sends the comment to the database', {
      LEAVE tagged-connection.disconnect;
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });
      tagged-connection.exec('SELECT 1');
      Notifications.unsubscribe($sub);

      expect(@sql[0].contains('controller:orders')).to.be-truthy;
    }
  }

  # Recency is an intrusive linked list over the cache keys, so a hit relinks in
  # constant time rather than rebuilding a list of every cached statement.
  context 'the cache eviction order', :order<defined>, {
    let(:small-cache, {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      $conn.prepared-statement-cache-size = 2;
      $conn;
    });

    it 'evicts the least recently used statement', {
      LEAVE small-cache.disconnect;

      small-cache.exec('SELECT 1');
      small-cache.exec('SELECT 2');
      small-cache.exec('SELECT 1');   # 2 is now the older of the two
      small-cache.exec('SELECT 3');

      expect(small-cache.cached-statement-count).to.eq(2);
    }

    it 'keeps the statement that was used most recently', {
      LEAVE small-cache.disconnect;

      small-cache.exec('SELECT 1');
      small-cache.exec('SELECT 2');
      small-cache.exec('SELECT 1');
      small-cache.exec('SELECT 3');

      # A hit on 1 does not grow the cache; an evicted 1 would have to prepare
      # again and push the count past the bound before the next eviction.
      small-cache.exec('SELECT 1');

      expect(small-cache.cached-statement-count).to.eq(2);
    }

    it 'empties on clear', {
      LEAVE small-cache.disconnect;

      small-cache.exec('SELECT 1');
      small-cache.clear-statement-cache;
      small-cache.exec('SELECT 2');

      expect(small-cache.cached-statement-count).to.eq(1);
    }
  }

  context 'caching enabled', :order<defined>, {
    it 'caches a prepared statement keyed by its sql', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');

      expect($conn.cached-statement-count).to.eq(1);
    }

    it 'reuses the cached statement for the same sql', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');
      $conn.exec('SELECT 1');

      expect($conn.cached-statement-count).to.eq(1);
    }

    it 'caches distinct statements separately', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');
      $conn.exec('SELECT 2');

      expect($conn.cached-statement-count).to.eq(2);
    }

    it 'returns correct rows when a cached statement is re-executed', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');
      expect($conn.exec('SELECT 1')[0][0].Int).to.eq(1);
    }
  }

  context 'cache size limit', :order<defined>, {
    it 'evicts the least-recently-used statement past the cache size', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;
      $conn.prepared-statement-cache-size = 1;
      LEAVE $conn.disconnect;

      $conn.exec('SELECT 1');
      $conn.exec('SELECT 2');

      expect($conn.cached-statement-count).to.eq(1);
    }
  }

  context 'cache lifecycle on disconnect', :order<defined>, {
    it 'clears the cache when the connection is disconnected', {
      my $conn = DB.shared.build-connection;
      $conn.prepared-statements = True;

      $conn.exec('SELECT 1');
      $conn.disconnect;

      expect($conn.cached-statement-count).to.eq(0);
    }
  }
}

my &pg-it = $is-pg ?? &it !! &xit;

describe 'PostgreSQL statement timeouts take effect', :tag<destructive>, {
  sub timeout-adapter(*%opts --> PgAdapter) {
    my %c = DB.read-config(name => 'primary');
    PgAdapter.new(
      schema   => %c<schema> // 'public',
      host     => %c<host> // 'localhost',
      database => %c<name> // %c<database>,
      user     => %c<user> // '',
      password => %c<password> // '',
      |%opts,
    );
  }

  pg-it 'applies the statement timeout to the session', {
    my $pg = timeout-adapter(statement-timeout => '7s');
    LEAVE $pg.disconnect;
    expect($pg.exec('SHOW statement_timeout')[0][0].Str).to.eq('7s');
  }

  pg-it 'applies the lock timeout to the session', {
    my $pg = timeout-adapter(lock-timeout => '3s');
    LEAVE $pg.disconnect;
    expect($pg.exec('SHOW lock_timeout')[0][0].Str).to.eq('3s');
  }

  pg-it 'applies the idle-in-transaction session timeout', {
    my $pg = timeout-adapter(idle-in-transaction-session-timeout => '10s');
    LEAVE $pg.disconnect;
    expect($pg.exec('SHOW idle_in_transaction_session_timeout')[0][0].Str).to.eq('10s');
  }
}
