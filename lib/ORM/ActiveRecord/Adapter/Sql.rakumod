
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

# Shared, dialect-neutral SQL building. Engine-specific adapters (PgAdapter,
# SqliteAdapter, MySqlAdapter) extend this class and override the bits that
# vary: connection params, bind syntax, INSERT shape, schema introspection,
# DDL emission, and read/write type coercion.
class SqlAdapter does Adapter is export {
  has $.db is rw;
  has Int $.txn-depth = 0;
  has Int $!sp-counter = 0;
  has @!txn-frames;

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
    $!txn-depth = 0;
    $!sp-counter = 0;
    @!txn-frames = ();
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

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self!ensure-connected;
    Log.sql(:sql($stmt.sql));
    my $query = $!db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    $query.allrows(:array-of-hash);
  }

  method explain(SqlStmt:D $stmt --> Str) {
    my $explain-stmt = SqlStmt.new(:adapter(self));
    $explain-stmt.sql = 'EXPLAIN ' ~ $stmt.sql;
    $explain-stmt.binds = $stmt.binds;
    my @rows = self.exec-stmt($explain-stmt);
    @rows.map({ $_.list.map(*.Str).join(' | ') }).join("\n");
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

  method begin(Str :$isolation)    { self.begin-sql(:$isolation) }
  method commit   { self.txn-exec('COMMIT') }
  method rollback { self.txn-exec('ROLLBACK') }

  method is-in-transaction(--> Bool) { $!txn-depth > 0 }

  method begin-sql(Str :$isolation) {
    if $isolation.defined && $isolation.chars {
      my $clause = self.isolation-clause($isolation);
      self.txn-exec("BEGIN $clause");
    } else {
      self.txn-exec('BEGIN');
    }
  }

  method isolation-clause(Str:D $isolation --> Str) {
    'ISOLATION LEVEL ' ~ self.normalise-isolation($isolation);
  }

  method normalise-isolation(Str:D $iso --> Str) {
    my $u = $iso.uc.subst('_', ' ', :g).subst(/\s+/, ' ', :g).trim;
    given $u {
      when 'READ UNCOMMITTED' | 'READ COMMITTED' | 'REPEATABLE READ' | 'SERIALIZABLE' { $u }
      default { die "transaction: unknown isolation level '$iso'" }
    }
  }

  method savepoint(Str:D $name)             { self.txn-exec("SAVEPOINT $name") }
  method release-savepoint(Str:D $name)     { self.txn-exec("RELEASE SAVEPOINT $name") }
  method rollback-to-savepoint(Str:D $name) { self.txn-exec("ROLLBACK TO SAVEPOINT $name") }

  method transaction(&block, Bool:D :$requires-new = False, Str :$isolation) {
    if $isolation.defined && $isolation.chars {
      die "transaction: isolation level only applies to the outermost transaction"
        if $!txn-depth > 0;
      self.normalise-isolation($isolation);
    }

    if $!txn-depth == 0 {
      self.begin-sql(:$isolation);
      $!txn-depth = 1;
      $!sp-counter = 0;
      self!push-txn-frame;
      return self!run-outer(&block);
    }

    return self!run-joined(&block) unless $requires-new;

    my $name = self!next-savepoint;
    self.savepoint($name);
    $!txn-depth++;
    self!push-txn-frame;
    self!run-savepoint($name, &block);
  }

  method !run-outer(&block) {
    my $result;
    my $rolled-back = False;
    {
      CATCH {
        when X::Rollback {
          self.rollback;
          $!txn-depth = 0;
          $rolled-back = True;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
        }
        default {
          self.rollback;
          $!txn-depth = 0;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
          .rethrow;
        }
      }
      $result = block();
    }
    return Nil if $rolled-back;
    self.commit;
    $!txn-depth = 0;
    my $frame = self!pop-txn-frame;
    self!fire-commit-frame($frame);
    $result;
  }

  method !run-joined(&block) {
    block();
  }

  method !run-savepoint(Str:D $name, &block) {
    my $result;
    my $rolled-back = False;
    {
      CATCH {
        when X::Rollback {
          self.rollback-to-savepoint($name);
          self.release-savepoint($name);
          $!txn-depth--;
          $rolled-back = True;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
        }
        default {
          self.rollback-to-savepoint($name);
          self.release-savepoint($name);
          $!txn-depth--;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
          .rethrow;
        }
      }
      $result = block();
    }
    return Nil if $rolled-back;
    self.release-savepoint($name);
    $!txn-depth--;
    self!merge-txn-frame-into-parent;
    $result;
  }

  method !push-txn-frame { @!txn-frames.push: { records => {}, order => [] } }
  method !pop-txn-frame  { @!txn-frames.pop }

  method !merge-txn-frame-into-parent {
    my $top = @!txn-frames.pop;
    return unless @!txn-frames.elems;
    my $parent = @!txn-frames[*-1];
    for $top<order>.list -> $key {
      my %entry = $top<records>{$key};
      if $parent<records>{$key}:exists {
        for %entry<kinds>.keys -> $k {
          $parent<records>{$key}<kinds>{$k} = True;
        }
      } else {
        $parent<records>{$key} = %entry;
        $parent<order>.push: $key;
      }
    }
  }

  method register-txn-callback(Mu:D $record, Str:D $kind) {
    unless @!txn-frames.elems {
      self!fire-commit-record($record, %($kind => True));
      return;
    }
    my $key = $record.WHICH.Str;
    my $frame = @!txn-frames[*-1];
    unless $frame<records>{$key}:exists {
      $frame<records>{$key} = %(record => $record, kinds => {});
      $frame<order>.push: $key;
    }
    $frame<records>{$key}<kinds>{$kind} = True;
  }

  method !fire-commit-frame($frame) {
    return unless $frame.defined;
    for $frame<order>.list -> $key {
      my %entry = $frame<records>{$key};
      self!fire-commit-record(%entry<record>, %entry<kinds>);
    }
  }

  method !fire-rollback-frame($frame) {
    return unless $frame.defined;
    for $frame<order>.list -> $key {
      my %entry = $frame<records>{$key};
      self!fire-rollback-record(%entry<record>, %entry<kinds>);
    }
  }

  method !fire-commit-record(Mu:D $rec, %kinds) {
    return unless $rec.^can('run-after-commit');
    $rec.run-after-commit(:%kinds);
  }

  method !fire-rollback-record(Mu:D $rec, %kinds) {
    return unless $rec.^can('run-after-rollback');
    $rec.run-after-rollback(:%kinds);
  }

  method !next-savepoint(--> Str) {
    $!sp-counter++;
    'ar_sp_' ~ $!sp-counter;
  }

  # DBDish::mysql rejects transaction-control statements via prepare(),
  # so callers must use this path instead of exec() for BEGIN / COMMIT /
  # ROLLBACK / SAVEPOINT / SET TRANSACTION.
  method txn-exec(Str:D $sql) {
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

  method build-update-where(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-value-sets($stmt, :%attrs, :%types);
    die 'update-all: no columns to update' unless $values.chars;
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    $stmt.sql = "UPDATE $table SET $values $where-clause";
    $stmt;
  }

  method build-update-counters-where(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups --> SqlStmt) {
    die 'update-counters: no counters supplied' unless %counters.elems;
    my $stmt = SqlStmt.new(:adapter(self));
    my @parts;
    for %counters.kv -> $col, $n {
      my $ph = $stmt.placeholder($n);
      @parts.push: "$col = COALESCE($col, 0) + $ph";
    }
    my $sets = @parts.join(', ');
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    $stmt.sql = "UPDATE $table SET $sets $where-clause";
    $stmt;
  }

  method union-insert-keys(@rows, Bool:D :$include-id = False) {
    my %seen;
    my @order;
    for @rows -> %row {
      for %row.keys -> $k {
        next if $k eq 'id' && !$include-id;
        next if $k ~~ /_confirmation$/;
        unless %seen{$k} {
          %seen{$k} = True;
          @order.push: $k;
        }
      }
    }
    @order;
  }

  method build-insert-many(Str:D :$table, :@rows, :%types = {}, :@keys = (), Bool:D :$include-id = False --> SqlStmt) {
    die 'insert-all: no rows supplied' unless @rows.elems;
    my @cols = @keys.elems ?? @keys.list !! self.union-insert-keys(@rows, :$include-id);
    die 'insert-all: no columns to insert' unless @cols.elems;

    my $stmt = SqlStmt.new(:adapter(self));
    my $fields = @cols.join(', ');
    my @clauses;
    for @rows -> %row {
      my @parts;
      for @cols -> $k {
        if %row{$k}:exists && %row{$k}.defined {
          my $type = %types{$k} // Str;
          @parts.push: self!bind-typed($stmt, %row{$k}, :$type);
        } else {
          @parts.push: 'NULL';
        }
      }
      @clauses.push: '(' ~ @parts.join(', ') ~ ')';
    }
    $stmt.sql = "INSERT INTO $table ($fields) VALUES " ~ @clauses.join(', ');
    $stmt;
  }

  # Set-based UPDATE — dialect overrides handle row-count retrieval.
  method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups --> Int) { ... }
  method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups --> Int) { ... }

  # Bulk INSERT / UPSERT — dialect-specific shape.
  method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List) { ... }
  method upsert-records(Str:D :$table, :@rows, :%types = {}, :@unique-by = (), :@update-cols = () --> Int) { ... }

  method without-excluded-fields(%attrs) {
    for %attrs.keys { %attrs{$_}:delete if $_ ~~ /_confirmation$/ }
    %attrs;
  }

  method build-select(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $body = self.build-select-body(
      $stmt, :$table, :$join-table, :@fields, :%where, :%where-not, :@or-groups,
      :@order, :$limit, :$offset, :$distinct, :@group, :@having,
      :$from-source, :$from-alias, :@joins, :@optimizer-hints,
    );
    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix
      ?? "$cte-prefix\n$annotated"
      !! $annotated;
    $stmt;
  }

  method build-select-body(SqlStmt:D $stmt, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@optimizer-hints --> Str) {
    my $select-keyword = $distinct ?? 'SELECT DISTINCT' !! 'SELECT';
    my $hints = self.format-optimizer-hints(@optimizer-hints);
    $select-keyword ~= " $hints" if $hints;
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $select = @fields.map({
      my $n = $_.name;
      $n.contains('(') || $n.contains('.') || $n.contains(' ')
        ?? $n !! "$qualifier.$n"
    }).join(', ');
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

    qq:to/SQL/;
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
  }

  method build-ctes(SqlStmt:D $stmt, :@ctes --> Str) {
    return '' unless @ctes.elems;
    my $is-recursive = @ctes.first({ $_<recursive> }).so;
    my @parts;
    for @ctes -> %cte {
      my $name = %cte<name>;
      my $sub = %cte<sub>;
      my $sub-sql;
      given $sub {
        when Str { $sub-sql = $sub.trim }
        default {
          if $sub.^can('to-sql-into') {
            $sub-sql = $sub.to-sql-into($stmt).trim;
          } else {
            die "with: unsupported CTE sub-query type {$sub.^name}";
          }
        }
      }
      @parts.push: "$name AS ($sub-sql)";
    }
    ($is-recursive ?? 'WITH RECURSIVE ' !! 'WITH ') ~ @parts.join(', ');
  }

  method format-optimizer-hints(@hints --> Str) {
    return '' unless @hints.elems;
    '/*+ ' ~ @hints.join(' ') ~ ' */';
  }

  method attach-annotations(Str:D $sql, :@annotations --> Str) {
    return $sql unless @annotations.elems;
    my $trimmed = $sql.subst(/\s+$/, '');
    my $tags = @annotations.map({ '/* ' ~ self!sanitize-comment($_) ~ ' */' }).join(' ');
    "$trimmed $tags\n";
  }

  method !sanitize-comment(Str:D $c --> Str) {
    $c.subst('*/', '* /', :g);
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
        when Associative {
          my %h = $entry.Hash;
          my @hp = self!where-fragments($stmt, %h, '=', :qualifier(Str));
          @fragments.push: @hp.join(' AND ') if @hp.elems;
        }
        when Str        { @fragments.push: $entry }
        when Positional {
          my @parts = $entry.list;
          if @parts.elems && @parts[0] ~~ Pair {
            my %h = @parts.Hash;
            my @hp = self!where-fragments($stmt, %h, '=', :qualifier(Str));
            @fragments.push: @hp.join(' AND ') if @hp.elems;
          } else {
            @fragments.push: $stmt.interpolate(@parts[0].Str, |@parts[1..*]);
          }
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
        my $lo-bounded = $lo.defined && $lo !~~ -Inf;
        my $hi-bounded = $hi.defined && $hi !~~ Inf;
        my @parts;
        if $lo-bounded {
          my $lo-op = $v.excludes-min ?? '>' !! '>=';
          @parts.push: "$col $lo-op " ~ $stmt.placeholder($lo);
        }
        if $hi-bounded {
          my $hi-op = $v.excludes-max ?? '<' !! '<=';
          @parts.push: "$col $hi-op " ~ $stmt.placeholder($hi);
        }
        die "Range $v has no bounded endpoints" unless @parts.elems;
        my $inner = @parts.join(' AND ');
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

  method get-objects(Mu:U :$class, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my @records = self.get-records(:@fields, :$table, :$join-table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints);
    my @objects;

    for @records.kv -> $k, $record {
      my $obj = $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $record = self.get-record(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints);
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

  method get-records(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my @records;
    my $stmt = self.build-select(:@fields, :$join-table, :$table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints);

    for self.exec-stmt($stmt).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field {
        %record{$field.name} = self.coerce-read($row[$kk], type => $field.type);
      }
      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $stmt = self.build-select(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, limit => 1, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints);
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

  method count-records(Str:D :$table, :%where, :%where-not, :@or-groups, Bool:D :$distinct=False, :@select, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';
    my $hints = self.format-optimizer-hints(@optimizer-hints);
    my $hints-sp = $hints ?? " $hints" !! '';

    if @group.elems || @having.elems {
      my $inner = SqlStmt.new(:adapter(self));
      my $cte-prefix = self.build-ctes($inner, :@ctes);
      my $where-sql = self.build-where($inner, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
      my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
      my $group-clause = @group.elems ?? "GROUP BY @group.join(', ')" !! '';
      my $having-clause = self.build-having($inner, @having);
      my $body = qq:to/SQL/;
        SELECT count(*)$hints-sp FROM (
          SELECT 1 $from-clause
          $joins-sql
          $where-clause
          $group-clause
          $having-clause
        ) sub
        SQL
      my $annotated = self.attach-annotations($body, :@annotations);
      $inner.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;
      return self.exec-stmt($inner)[0][0].Int;
    }

    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    my $body;

    if $distinct {
      if @joins.elems && !@select.elems {
        $body = qq:to/SQL/;
          SELECT count(DISTINCT $qualifier.id)$hints-sp
          $from-clause
          $joins-sql
          $where-clause
          SQL
      } else {
        my $cols = @select.elems ?? @select.join(', ') !! '*';
        $body = qq:to/SQL/;
          SELECT count(*)$hints-sp
          FROM (
            SELECT DISTINCT $cols
            $from-clause
            $joins-sql
            $where-clause
          ) sub
          SQL
      }
    } else {
      $body = qq:to/SQL/;
        SELECT count(*)$hints-sp
        $from-clause
        $joins-sql
        $where-clause
        SQL
    }

    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;
    self.exec-stmt($stmt)[0][0].Int;
  }

  method aggregate(Str:D :$table, Str:D :$op, :$col is copy, :%where, :%where-not, :@or-groups, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $hints = self.format-optimizer-hints(@optimizer-hints);
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    my $needs-qualifier = @joins.elems.so;
    my $agg-col = self!agg-col-expr($op, $col, $distinct, $qualifier, $needs-qualifier);
    my $group-list = @group.map({ self!qualify-if-bare($_, $qualifier, $needs-qualifier) }).join(', ');
    my $group-clause = @group.elems ?? "GROUP BY $group-list" !! '';
    my $having-clause = self.build-having($stmt, @having);

    my $select-cols = @group.elems ?? "$group-list, $agg-col" !! $agg-col;
    my $select-keyword = $hints ?? "SELECT $hints" !! 'SELECT';

    my $body = qq:to/SQL/;
      $select-keyword $select-cols
      $from-clause
      $joins-sql
      $where-clause
      $group-clause
      $having-clause
      SQL
    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;

    my @rows = self.exec-stmt($stmt);

    if @group.elems {
      my %result;
      my $gn = @group.elems;
      for @rows -> $row {
        my $key = $gn == 1 ?? $row[0] !! $row[0 ..^ $gn].List;
        %result{ $key } = self!coerce-agg-value($op, $row[$gn]);
      }
      return %result;
    }
    return self!agg-empty-default($op) unless @rows.elems;
    self!coerce-agg-value($op, @rows[0][0]);
  }

  method !agg-col-expr(Str:D $op, $col, Bool:D $distinct, Str:D $qualifier, Bool:D $needs-qualifier --> Str) {
    if $op eq 'COUNT' {
      return 'COUNT(*)' unless $col.defined && $col.Str.chars && $col.Str ne '*';
      my $c = self!qualify-if-bare($col.Str, $qualifier, $needs-qualifier);
      return $distinct ?? "COUNT(DISTINCT $c)" !! "COUNT($c)";
    }
    die "$op requires a column" unless $col.defined && $col.Str.chars;
    my $c = self!qualify-if-bare($col.Str, $qualifier, $needs-qualifier);
    $op ~ '(' ~ $c ~ ')';
  }

  method !qualify-if-bare(Str:D $name, Str:D $qualifier, Bool:D $needs-qualifier --> Str) {
    return $name unless $needs-qualifier;
    return $name if $name.contains('(') || $name.contains('.') || $name.contains(' ');
    "$qualifier.$name";
  }

  method !coerce-agg-value(Str:D $op, $value) {
    return self!agg-empty-default($op) without $value;
    given $op {
      when 'COUNT' { $value.Str.Int }
      when 'SUM' | 'AVG' {
        my $s = $value.Str;
        $s.contains('.') ?? $s.Rat !! $s.Int;
      }
      default { $value }
    }
  }

  method !agg-empty-default(Str:D $op) {
    given $op {
      when 'COUNT' { 0 }
      when 'SUM'   { 0 }
      default      { Nil }
    }
  }

  # DDL — engines override. Default impls cover the SQL that's actually
  # portable (DROP TABLE, ALTER TABLE DROP COLUMN, plain CREATE INDEX).
  method ddl-create-table(Str:D $table, @params, :@foreign-keys) { ... }
  method ddl-add-column(Str:D $table, Pair:D $param)             { ... }
  method ddl-add-timestamps(Str:D $table)                        { ... }

  method ddl-drop-table(Str:D $table) {
    self.exec("DROP TABLE $table");
  }

  # Drop every table the adapter can see. Adapters override to disable FK
  # checks for the duration of the drops so order does not matter.
  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    self.ddl-drop-table($_) for @tables;
    @tables;
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
