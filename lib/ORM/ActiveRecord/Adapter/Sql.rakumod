
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql::Exec;
use ORM::ActiveRecord::Adapter::Sql::Transactions;
use ORM::ActiveRecord::Adapter::Sql::Builders;
use ORM::ActiveRecord::Adapter::Sql::Aggregates;
use ORM::ActiveRecord::Adapter::Sql::Ddl;
use ORM::ActiveRecord::Adapter::Sql::Guards;

# Dialect-neutral base; per-engine adapters override dialect-specific bits.
class SqlAdapter
  does Adapter
  does SqlExec
  does SqlTransactions
  does SqlBuilders
  does SqlAggregates
  does SqlDdl
  does SqlGuards
  is export
{
  has $.db is rw;

  # Engine-specific — must be overridden
  method connect()                                                  { ... }
  method bind-placeholder(Int:D $n --> Str)                         { ... }
  method get-fields(Str:D :$table)                                  { ... }
  method get-table-names()                                          { ... }
  method get-indexes(Str:D :$table --> List)                        { ... }
  method get-constraints(Str:D :$table --> List)                    { ... }
  method get-sequences(--> List)                                    { ... }
  method build-insert(Str:D :$table, :%attrs, :%types --> SqlStmt)  { ... }
  method create-object(Mu:D $obj)                                   { ... }
  method delete-records(Str:D :$table, :%where, :%where-not --> Int) { ... }

  # Set-based UPDATE / INSERT / UPSERT — dialect-specific shape; engines override.
  method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) { ... }
  method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int)   { ... }
  method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List)   { ... }
  method upsert-records(Str:D :$table, :@rows, :%types = {}, :@unique-by = (), :@update-cols = () --> Int) { ... }

  # DDL — engines override.
  method ddl-create-table(Str:D $table, @params, :@foreign-keys, :$id, :$primary-key) { ... }
  method ddl-add-column(Str:D $table, Pair:D $param)             { ... }
  method ddl-add-timestamps(Str:D $table)                        { ... }

  # Lifecycle — generic across DBIish drivers; engines just need to set $!db
  method is-connected(--> Bool) { $!db.defined.so }

  method disconnect(--> Bool) {
    return False unless $!db.defined;
    self.clear-statement-cache;
    self.clear-query-cache;
    $!db.dispose;
    $!db = Nil;
    self.reset-txn-state;
    True;
  }

  method reconnect() {
    self.disconnect;
    self.connect;
    self;
  }

  # Health probe: a defined handle is not proof the server is still there, so
  # run a trivial round-trip. Returns False (never throws) on a dropped or
  # dead connection.
  method is-active(--> Bool) {
    return False unless self.is-connected;
    (try { self.exec('SELECT 1'); True }) // False;
  }

  # Verify the connection, reconnecting once if it is dead. Returns whether the
  # connection is live afterward.
  method verify(--> Bool) {
    return True if self.is-active;
    self.reconnect;
    self.is-active;
  }
}
