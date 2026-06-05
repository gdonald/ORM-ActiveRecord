use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Pg;

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
