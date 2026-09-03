
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Schema::Field;
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
  has %!field-objects-cache;
  has %!field-map-cache;
  has %!field-types-cache;
  has %!field-defaults-cache;
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

  # The same `Field` objects every model instance and every relation over this
  # table shares. `Field` is immutable, so one list serves them all instead of
  # each caller rebuilding one object per column.
  method get-field-objects(Str:D :$table) {
    return @(%!field-objects-cache{$table}) if %!field-objects-cache{$table}:exists;
    my @fields = self.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    %!field-objects-cache{$table} = @fields;
    @fields
  }

  # The starting attribute value for each of a table's columns, keyed by column
  # name. Computed once per table so instantiation does not re-derive a default
  # from the column type for every column of every row.
  method get-field-defaults(Str:D :$table --> Hash) {
    return %!field-defaults-cache{$table} if %!field-defaults-cache{$table}:exists;

    my %defaults;
    for self.get-field-objects(:$table) -> $field {
      next if $field.name eq 'id';
      %defaults{$field.name} = self.default-for-type($field.type);
    }

    %!field-defaults-cache{$table} = %defaults;
    %defaults
  }

  # Name-keyed views of the same cached field list, so a lookup by column name
  # is a hash hit rather than a scan. Callers read these; they do not mutate.
  method get-field-map(Str:D :$table --> Hash) {
    return %!field-map-cache{$table} if %!field-map-cache{$table}:exists;

    my %map;
    for self.get-field-objects(:$table) -> $field { %map{$field.name} = $field }

    %!field-map-cache{$table} = %map;
  }

  method get-field-types(Str:D :$table --> Hash) {
    return %!field-types-cache{$table} if %!field-types-cache{$table}:exists;

    my %types;
    for self.get-field-objects(:$table) -> $field { %types{$field.name} = $field.type }

    %!field-types-cache{$table} = %types;
  }

  # Which coercion a column type needs, decided once per (dialect, type string).
  # `coerce-read` and `coerce-write` classified the type with up to four regex
  # matches on every value, so a ten-column row cost forty matches. A profile of
  # loading rows showed the regex engine taking 13% of the run. Each engine spells
  # its types differently, so the classification itself stays per adapter and
  # only the memoisation is shared.
  has %!coercion-kind;

  method coercion-kind(Str $type --> Str) {
    return 'none' without $type;
    %!coercion-kind{$type} //= self.classify-type($type);
  }

  method classify-type(Str:D $type --> Str) { ... }

  # The strings each database spells a boolean with. A `Set` rather than a
  # chain of `|`, which allocated a Junction per value read.
  my constant TRUE-TEXT  = set <t true 1 y yes>;
  my constant FALSE-TEXT = set <f false 0 n no>;

  method coerce-bool($value) {
    return $value if $value ~~ Bool;
    my $s = $value.Str.lc;
    return True  if TRUE-TEXT{$s};
    return False if FALSE-TEXT{$s};
    $value.so;
  }

  method default-for-type(Str:D $type) {
    given $type {
      when /integer/ { 0 }
      when /(character|text)/ { '' }
      when /numeric|decimal|real|double|float|money/ { 0 }
      when /boolean/ { False }
      when /timestamp|^date|^time/ { DateTime }
      default { die 'Unknown field type: ' ~ $type }
    }
  }

  method column-details(Str:D :$table --> List) {
    return @(%!column-details-cache{$table}) if %!column-details-cache{$table}:exists;
    my @details = self.column-details-uncached(:$table);
    %!column-details-cache{$table} = @details;
    @details
  }

  method clear-schema-cache {
    %!fields-cache          = ();
    %!field-objects-cache   = ();
    %!field-map-cache       = ();
    %!field-types-cache     = ();
    %!field-defaults-cache  = ();
    %!column-details-cache  = ();
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
