
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql::Exec;
use ORM::ActiveRecord::Adapter::Sql::Transactions;
use ORM::ActiveRecord::Adapter::Sql::Builders;
use ORM::ActiveRecord::Adapter::Sql::Aggregates;
use ORM::ActiveRecord::Adapter::Sql::Ddl;
use ORM::ActiveRecord::Adapter::Sql::Guards;
use ORM::ActiveRecord::Adapter::Sql::AdvisoryLocks;

# Dialect-neutral base; per-engine adapters override dialect-specific bits.
class SqlAdapter
  does Adapter
  does SqlExec
  does SqlTransactions
  does SqlBuilders
  does SqlAggregates
  does SqlDdl
  does SqlGuards
  does SqlAdvisoryLocks
  is export
{
  has $.db is rw;
  has %!fields-cache;
  has %!column-details-cache;

  # Column metadata comes from information_schema, which is expensive to query
  # on every model operation, so memoise it per table for the life of the
  # connection. A schema change (DDL) clears it, and disconnect drops it with
  # the rest of the connection state.
  method get-fields(Str:D :$table) {
    return @(%!fields-cache{$table}) if %!fields-cache{$table}:exists;
    my @fields = self.get-fields-uncached(:$table);
    %!fields-cache{$table} = @fields;
    @fields
  }

  method column-details(Str:D :$table --> List) {
    return @(%!column-details-cache{$table}) if %!column-details-cache{$table}:exists;
    my @details = self.column-details-uncached(:$table);
    %!column-details-cache{$table} = @details;
    @details
  }

  method clear-schema-cache {
    %!fields-cache         = ();
    %!column-details-cache = ();
  }

  # Engine-specific — must be overridden
  method connect()                                                  { ... }
  method bind-placeholder(Int:D $n --> Str)                         { ... }
  method get-fields-uncached(Str:D :$table)                         { ... }
  method column-details-uncached(Str:D :$table --> List)            { ... }
  method get-table-names()                                          { ... }
  method get-indexes(Str:D :$table --> List)                        { ... }
  method get-constraints(Str:D :$table --> List)                    { ... }
  method get-foreign-keys(Str:D :$table --> List)                   { ... }
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

  # Serialized: tearing down the driver handle while another thread is
  # mid-statement on it would free the handle under that statement.
  method disconnect(--> Bool) {
    self.serialized: {
      return False unless $!db.defined;
      self.clear-statement-cache;
      self.clear-query-cache;
      self.clear-schema-cache;
      # A handle whose connection already died can throw on dispose; drop it
      # regardless so a reconnect is never blocked by a dead one.
      (try $!db.dispose);
      $!db = Nil;
      self.reset-txn-state;
      True;
    }
  }

  method reconnect() {
    self.serialized: {
      self.disconnect;
      self.connect;
      self;
    }
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
