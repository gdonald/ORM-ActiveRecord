
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql::Exec;
use ORM::ActiveRecord::Adapter::Sql::Transactions;
use ORM::ActiveRecord::Adapter::Sql::Builders;
use ORM::ActiveRecord::Adapter::Sql::Aggregates;
use ORM::ActiveRecord::Adapter::Sql::Ddl;

# Dialect-neutral base; per-engine adapters override dialect-specific bits.
class SqlAdapter
  does Adapter
  does SqlExec
  does SqlTransactions
  does SqlBuilders
  does SqlAggregates
  does SqlDdl
  is export
{
  has $.db is rw;

  # Engine-specific — must be overridden
  method connect()                                                  { ... }
  method bind-placeholder(Int:D $n --> Str)                         { ... }
  method get-fields(Str:D :$table)                                  { ... }
  method get-table-names()                                          { ... }
  method build-insert(Str:D :$table, :%attrs, :%types --> SqlStmt)  { ... }
  method create-object(Mu:D $obj)                                   { ... }
  method delete-records(Str:D :$table, :%where, :%where-not --> Int) { ... }

  # Set-based UPDATE / INSERT / UPSERT — dialect-specific shape; engines override.
  method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) { ... }
  method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int)   { ... }
  method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List)   { ... }
  method upsert-records(Str:D :$table, :@rows, :%types = {}, :@unique-by = (), :@update-cols = () --> Int) { ... }

  # DDL — engines override.
  method ddl-create-table(Str:D $table, @params, :@foreign-keys) { ... }
  method ddl-add-column(Str:D $table, Pair:D $param)             { ... }
  method ddl-add-timestamps(Str:D $table)                        { ... }

  # Lifecycle — generic across DBIish drivers; engines just need to set $!db
  method is-connected(--> Bool) { $!db.defined.so }

  method disconnect(--> Bool) {
    return False unless $!db.defined;
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
}
