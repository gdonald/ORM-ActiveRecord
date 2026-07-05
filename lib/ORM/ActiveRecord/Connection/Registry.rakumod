use ORM::ActiveRecord::DB;

# A request-scoped set of checked-out connections, one per named connection the
# request actually touches. The first query on a connection checks a connection
# out of that connection's pool and caches it here; every later query on the same
# connection reuses it, so the whole request sees a consistent connection (and its
# transaction). `release-all` returns them to their pools when the request ends.
#
# Unlike the single `$*AR-DB-OVERRIDE`, this is keyed by connection name, so an
# app with a replica or several databases routes each model to its own pooled
# connection instead of forcing everything onto one.
class ORM::ActiveRecord::Connection::Registry is export {
  has Lock $!lock = Lock.new;
  has %!entries;   # connection-name => %( pool => ConnectionPool, conn => Adapter, db => DB )

  method db-for(Str:D $name --> DB) {
    $!lock.protect: {
      return %!entries{$name}<db> if %!entries{$name}:exists;

      my $pool = DB.shared(name => $name).pool;
      my $conn = $pool.checkout;
      my $db   = DB.new(:adapter($conn), :$name);

      %!entries{$name} = %( :$pool, :$conn, :$db );
      $db;
    }
  }

  method release-all(--> Nil) {
    $!lock.protect: {
      for %!entries.values -> %entry { %entry<pool>.checkin(%entry<conn>) }
      %!entries = ();
    }
  }

  method checked-out-names(--> List) {
    $!lock.protect: { %!entries.keys.sort.List }
  }
}
