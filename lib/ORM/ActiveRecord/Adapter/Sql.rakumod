
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

# Shared, dialect-neutral SQL building. Engine-specific adapters (PgAdapter,
# SqliteAdapter, MySqlAdapter) extend this class and override the bits that
# vary: connection params, bind syntax, INSERT shape, schema introspection,
# DDL emission, and read/write type coercion.
class SqlAdapter does Adapter is export {
  has $.db is rw;

  # Engine-specific — must be overridden
  method connect()              { ... }
  method bind-placeholder(Int:D $n --> Str) { ... }
  method get-fields(Str:D :$table) { ... }
  method get-table-names()      { ... }
  method build-insert(Str:D :$table, :%attrs, :%types --> SqlStmt) { ... }
  method create-object(Mu:D $obj) { ... }
  method delete-records(Str:D :$table, :%where, :%where-not --> Int) { ... }

  # Lifecycle — generic across DBIish drivers; engines just need to set $!db
  method is-connected(--> Bool) { $!db.defined.so }

  method disconnect(--> Bool) {
    return False unless $!db.defined;
    $!db.dispose;
    $!db = Nil;
    True;
  }

  method reconnect() {
    self.disconnect;
    self.connect;
    self;
  }

  method !ensure-connected { self.connect unless $!db.defined }

  method exec(Str:D $sql, *@binds) {
    self!ensure-connected;
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute(|@binds);
    $query.allrows;
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self!ensure-connected;
    Log.sql(:sql($stmt.sql));
    my $query = $!db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    $query.allrows;
  }

  method sanitize-sql-array(@parts --> SqlStmt) {
    SqlStmt.new(:adapter(self)).sanitize-array(@parts);
  }

  method sanitize-sql($input --> SqlStmt) {
    given $input {
      when SqlStmt    { $input }
      when Positional { self.sanitize-sql-array($input.list) }
      when Str        {
        my $stmt = SqlStmt.new(:adapter(self));
        $stmt.sql = $input;
        $stmt;
      }
      default { die 'sanitize-sql: unsupported input type ' ~ $input.^name }
    }
  }

  method begin    { self!txn-exec('BEGIN') }
  method commit   { self!txn-exec('COMMIT') }
  method rollback { self!txn-exec('ROLLBACK') }

  method !txn-exec(Str:D $sql) {
    self!ensure-connected;
    Log.sql(:$sql);
    $!db.execute($sql);
  }

  method !bind-typed(SqlStmt:D $stmt, $value, Str :$type --> Str) {
    my $coerced = self.coerce-write($value, :$type);
    $coerced.defined
      ?? $stmt.placeholder($coerced)
      !! $stmt.placeholder('');
  }

  method build-value-sets(SqlStmt:D $stmt, :%attrs, :%types = {}) {
    my @values;
    for %attrs.keys {
      next if $_ ~~ 'id';
      next unless %attrs{$_}.defined;
      my $type = %types{$_};
      @values.push: "$_ = " ~ self!bind-typed($stmt, %attrs{$_}, :$type);
    }
    @values.join(', ');
  }

  method build-values-list(SqlStmt:D $stmt, :@values, :@types = []) {
    @values.kv.map(-> $i, $v {
      my $type = @types[$i] // Str;
      self!bind-typed($stmt, $v, :$type);
    }).join(', ');
  }

  method build-update(Str:D :$table, Int:D :$id, :%attrs, :%types = {} --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-value-sets($stmt, :%attrs, :%types);
    my $id-ph = $stmt.placeholder($id);

    $stmt.sql = qq:to/SQL/;
      UPDATE $table
      SET $values
      WHERE id = $id-ph
      SQL

    $stmt;
  }

  method without-excluded-fields(%attrs) {
    for %attrs.keys { %attrs{$_}:delete if $_ ~~ /_confirmation$/ }
    %attrs;
  }

  method build-select(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $select-keyword = $distinct ?? 'SELECT DISTINCT' !! 'SELECT';
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $select = @fields.map({ $qualifier ~ '.' ~ $_.name }).join(', ');
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    my $group-clause = @group ?? "GROUP BY @group.join(', ')" !! '';
    my $having-clause = self.build-having($stmt, @having);
    my $order = self.build-order($stmt, @order);
    my $limit_offset = self.limit-offset-clause(:$limit, :$offset);
    my $join = '';

    if $join-table {
      my $foreign-key = Utils.to-foreign-key($table);

      $join = qq:to/SQL/;
        LEFT JOIN $join-table
        ON $qualifier.id = $join-table.$foreign-key
      SQL
    }

    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';

    $stmt.sql = qq:to/SQL/;
      $select-keyword $select
	    $from-clause
      $join
      $joins-sql
      $where-clause
      $group-clause
      $having-clause
      $order
      $limit_offset
      SQL

    $stmt;
  }

  method limit-offset-clause(Int:D :$limit = 0, Int:D :$offset = 0 --> Str) {
    my $l = $limit  ?? "LIMIT $limit"   !! '';
    my $o = $offset ?? "OFFSET $offset" !! '';
    ($l, $o).grep(*.chars).join(' ');
  }

  method build-having(SqlStmt:D $stmt, @having --> Str) {
    return '' unless @having.elems;
    my @fragments;
    for @having -> $entry {
      given $entry {
        when Str        { @fragments.push: $entry }
        when Positional {
          my @parts = $entry.list;
          @fragments.push: $stmt.interpolate(@parts[0].Str, |@parts[1..*]);
        }
        default { die "build-having: unsupported entry type " ~ $entry.^name }
      }
    }
    "HAVING " ~ @fragments.map({ "($_)" }).join(' AND ');
  }

  method build-order(SqlStmt:D $stmt, @order --> Str) {
    return '' unless @order.elems;
    my @fragments;
    for @order -> $entry {
      given $entry {
        when Str        { @fragments.push: $entry }
        when Positional {
          my @parts = $entry.list;
          @fragments.push: $stmt.interpolate(@parts[0].Str, |@parts[1..*]);
        }
        default { die "build-order: unsupported entry type " ~ $entry.^name }
      }
    }
    "ORDER BY " ~ @fragments.join(', ');
  }

  method build-where(SqlStmt:D $stmt, %where, %where-not = {}, :@or-groups, Str :$qualifier --> Str) {
    my @parts;
    @parts.append: self!where-fragments($stmt, %where,     '=',  :$qualifier) if %where.elems;
    @parts.append: self!where-fragments($stmt, %where-not, '!=', :$qualifier) if %where-not.elems;
    my $base = @parts.elems ?? @parts.join(' AND ') !! '';

    return $base unless @or-groups.elems;

    my @clauses;
    @clauses.push: $base if $base;
    for @or-groups -> %g {
      my @gp;
      my %w  = %g<where>     // {};
      my %wn = %g<where-not> // {};
      @gp.append: self!where-fragments($stmt, %w,  '=',  :$qualifier) if %w.elems;
      @gp.append: self!where-fragments($stmt, %wn, '!=', :$qualifier) if %wn.elems;
      @clauses.push: @gp.join(' AND ') if @gp.elems;
    }
    return '' unless @clauses.elems;
    @clauses.elems == 1 ?? @clauses[0] !! @clauses.map({ "($_)" }).join(' OR ');
  }

  method !where-fragments(SqlStmt:D $stmt, %h, Str:D $op, Str :$qualifier) {
    my @out;
    for %h.kv -> $k, $v {
      if $v ~~ Hash {
        for $v.kv -> $col, $val {
          @out.push: self!fragment-for($stmt, "$k.$col", $op, $val);
        }
      } else {
        my $col = $qualifier.defined ?? "$qualifier.$k" !! $k;
        @out.push: self!fragment-for($stmt, $col, $op, $v);
      }
    }
    @out;
  }

  method !fragment-for(SqlStmt:D $stmt, Str:D $col, Str:D $op, $v --> Str) {
    my $negate = $op eq '!=';
    return $negate ?? "$col IS NOT NULL" !! "$col IS NULL"
      unless $v.defined;
    given $v {
      when Range {
        my $lo = $v.min;
        my $hi = $v.max;
        my $lo-op = $v.excludes-min ?? '>'  !! '>=';
        my $hi-op = $v.excludes-max ?? '<'  !! '<=';
        my $inner = "$col $lo-op " ~ $stmt.placeholder($lo)
                  ~ " AND $col $hi-op " ~ $stmt.placeholder($hi);
        $negate ?? "NOT ($inner)" !! $inner;
      }
      when Positional {
        my @vals = $v.list;
        unless @vals.elems {
          return $negate ?? 'TRUE' !! 'FALSE';
        }
        my $list = @vals.map({ $stmt.placeholder($_) }).join(', ');
        my $inop = $negate ?? 'NOT IN' !! 'IN';
        "$col $inop ($list)";
      }
      default {
        "$col $op " ~ $stmt.placeholder($v);
      }
    }
  }

  method get-objects(Mu:U :$class, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my @records = self.get-records(:@fields, :$table, :$join-table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins);
    my @objects;

    for @records.kv -> $k, $record {
      my $obj = $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my $record = self.get-record(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins);
    return Nil unless $record && $record{'id'};
    $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
  }

  method !types-from-fields(Mu:D $obj) {
    my %types;
    for $obj.fields -> $f { %types{$f.name} = $f.type }
    %types;
  }

  method update-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my %types = self!types-from-fields($obj);
    my $id = $obj.id;
    my $stmt = self.build-update(:$table, :%attrs, :%types, :$id);

    self.exec-stmt($stmt);
  }

  method get-rows(Str:D :$sql) {
    self.exec($sql);
  }

  method get-records(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my @records;
    my $stmt = self.build-select(:@fields, :$join-table, :$table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins);

    for self.exec-stmt($stmt).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field {
        %record{$field.name} = self.coerce-read($row[$kk], type => $field.type);
      }
      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my $stmt = self.build-select(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, limit => 1, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins);
    my $rows = self.exec-stmt($stmt);
    my %record;
    return %record unless $rows.elems;
    my $row = $rows[0];
    for @fields.kv -> $k, $field {
      %record{$field.name} = self.coerce-read($row[$k], type => $field.type);
    }

    %record;
  }

  method get-list(Str:D :$sql, Int:D :$col=0) {
    self.exec($sql);
  }

  method count-records(Str:D :$table, :%where, :%where-not, :@or-groups, Bool:D :$distinct=False, :@select, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';

    if @group.elems || @having.elems {
      my $inner = SqlStmt.new(:adapter(self));
      my $where-sql = self.build-where($inner, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
      my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
      my $group-clause = @group.elems ?? "GROUP BY @group.join(', ')" !! '';
      my $having-clause = self.build-having($inner, @having);
      $inner.sql = qq:to/SQL/;
        SELECT count(*) FROM (
          SELECT 1 $from-clause
          $joins-sql
          $where-clause
          $group-clause
          $having-clause
        ) sub
        SQL
      return self.exec-stmt($inner)[0][0].Int;
    }

    my $stmt = SqlStmt.new(:adapter(self));
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    if $distinct {
      if @joins.elems && !@select.elems {
        $stmt.sql = qq:to/SQL/;
          SELECT count(DISTINCT $qualifier.id)
          $from-clause
          $joins-sql
          $where-clause
          SQL
      } else {
        my $cols = @select.elems ?? @select.join(', ') !! '*';
        $stmt.sql = qq:to/SQL/;
          SELECT count(*)
          FROM (
            SELECT DISTINCT $cols
            $from-clause
            $joins-sql
            $where-clause
          ) sub
          SQL
      }
    } else {
      $stmt.sql = qq:to/SQL/;
        SELECT count(*)
        $from-clause
        $joins-sql
        $where-clause
        SQL
    }

    self.exec-stmt($stmt)[0][0].Int;
  }

  # DDL — engines override. Default impls cover the SQL that's actually
  # portable (DROP TABLE, ALTER TABLE DROP COLUMN, plain CREATE INDEX).
  method ddl-create-table(Str:D $table, @params, :@foreign-keys) { ... }
  method ddl-add-column(Str:D $table, Pair:D $param)             { ... }
  method ddl-add-timestamps(Str:D $table)                        { ... }

  method ddl-drop-table(Str:D $table) {
    self.exec("DROP TABLE $table");
  }

  method ddl-remove-column(Str:D $table, $field) {
    self.exec("ALTER TABLE $table DROP COLUMN $field");
  }

  method ddl-remove-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table DROP COLUMN created_at, DROP COLUMN updated_at");
  }

  method ddl-add-index(Str:D $table, Str:D :$name, Str:D :$columns, Bool:D :$unique = False) {
    my $u = $unique ?? 'UNIQUE ' !! '';
    self.exec("CREATE {$u}INDEX $name ON $table ($columns)");
  }

  method ddl-remove-index(Str:D :$name) {
    self.exec("DROP INDEX $name");
  }
}
