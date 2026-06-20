
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Environment;

# Asynchronous variants of the relation's read methods. Each runs the query on
# a worker thread against a dedicated connection checked out from this
# connection's pool (DBIish handles are not thread-safe, so the async work must
# not touch the shared connection), and returns a `Promise` that resolves to the
# usual result. `await` it, or `.result`.
role QueryAsync is export {
  method !async-connection-name(--> Str) {
    self.class-of.^can('connection-name')
      ?? self.class-of.connection-name
      !! default-connection();
  }

  method !run-async(&run) {
    my $name = self!async-connection-name;

    start {
      my $pool = DB.shared(name => $name).pool;
      my $conn = $pool.checkout;
      LEAVE $pool.checkin($conn);

      my $*AR-DB-OVERRIDE = DB.new(:adapter($conn), :$name);
      run(self);
    }
  }

  method load-async {
    my $name = self!async-connection-name;

    start {
      my $pool = DB.shared(name => $name).pool;
      my $conn = $pool.checkout;
      LEAVE $pool.checkin($conn);

      my $*AR-DB-OVERRIDE = DB.new(:adapter($conn), :$name);
      my @objects = self.perform;

      # The records were instantiated against the pooled connection; rebind them
      # to the shared connection before handing them to the calling thread.
      my $shared = DB.shared(name => $name);
      .rebind-db($shared) for @objects;

      @objects;
    }
  }

  method count-async(|args)      { self!run-async(-> $q { $q.count(|args) }) }
  method sum-async($col)         { self!run-async(-> $q { $q.sum($col) }) }
  method average-async($col)     { self!run-async(-> $q { $q.average($col) }) }
  method minimum-async($col)     { self!run-async(-> $q { $q.minimum($col) }) }
  method maximum-async($col)     { self!run-async(-> $q { $q.maximum($col) }) }
  method calculate-async(Str:D $op, $col?) { self!run-async(-> $q { $q.calculate($op, $col) }) }

  method pluck-async(*@cols)     { self!run-async(-> $q { $q.pluck(|@cols) }) }
  method pick-async(*@cols)      { self!run-async(-> $q { $q.pick(|@cols) }) }
  method ids-async               { self!run-async(-> $q { $q.ids }) }
}
