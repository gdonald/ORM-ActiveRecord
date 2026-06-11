
use JSON::Tiny;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Relation::Query::Json;
use ORM::ActiveRecord::Instrumentation::Notifications;

role SqlBuilders is export {
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

  method build-update-where(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-value-sets($stmt, :%attrs, :%types);
    my @sets;
    @sets.push: $values if $values.chars;
    for @locking-bump -> $col {
      @sets.push: "$col = COALESCE($col, 0) + 1";
    }
    die 'update-all: no columns to update' unless @sets.elems;
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    $stmt.sql = "UPDATE $table SET {@sets.join(', ')} $where-clause";
    $stmt;
  }

  method build-update-counters-where(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> SqlStmt) {
    die 'update-counters: no counters supplied' unless %counters.elems;
    my $stmt = SqlStmt.new(:adapter(self));
    my @parts;
    for %counters.kv -> $col, $n {
      my $ph = $stmt.placeholder($n);
      @parts.push: "$col = COALESCE($col, 0) + $ph";
    }
    for @locking-bump -> $col {
      @parts.push: "$col = COALESCE($col, 0) + 1";
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

  method without-excluded-fields(%attrs) {
    for %attrs.keys { %attrs{$_}:delete if $_ ~~ /_confirmation$/ }
    %attrs;
  }

  method build-select(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock = False --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $body = self.build-select-body(
      $stmt, :$table, :$join-table, :@fields, :%where, :%where-not, :@or-groups,
      :@order, :$limit, :$offset, :$distinct, :@group, :@having,
      :$from-source, :$from-alias, :@joins, :@optimizer-hints, :$lock,
    );
    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix
      ?? "$cte-prefix\n$annotated"
      !! $annotated;
    $stmt;
  }

  method build-select-body(SqlStmt:D $stmt, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@optimizer-hints, :$lock = False --> Str) {
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
    my $lock-clause = self.format-lock-clause($lock);

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
      $lock-clause
      SQL
  }

  # FOR UPDATE / FOR SHARE / FOR NO KEY UPDATE etc. Adapters may override.
  # `True` → 'FOR UPDATE'; a Str is emitted verbatim; falsy → no clause.
  method format-lock-clause($lock --> Str) {
    return '' without $lock;
    return '' if $lock === False;
    return 'FOR UPDATE' if $lock === True;
    return $lock.Str if $lock ~~ Str && $lock.chars;
    '';
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
        my $col = ($qualifier.defined && !$k.contains('.'))
                  ?? "$qualifier.$k" !! $k;
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
      when JsonPredicate {
        self.json-fragment($stmt, $col, $op, $v);
      }
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

  # ---- JSON / JSONB predicate operators ----

  method json-fragment(SqlStmt:D $stmt, Str:D $col, Str:D $op, JsonPredicate:D $p --> Str) {
    my $frag = do given $p.kind {
      when 'extract'  {
        self.json-extract-text-sql($col, @($p.path)) ~ " {$p.cmp} " ~ $stmt.placeholder($p.value);
      }
      when 'contains' { self.json-contains-sql($stmt, $col, $p.value) }
      when 'has-key'  { self.json-has-key-sql($stmt, $col, $p.value) }
    };

    $op eq '!=' ?? "NOT ($frag)" !! $frag;
  }

  # MySQL / SQLite share the `col ->> '$.a.b'` path syntax; PostgreSQL overrides.
  method json-path-expr(@path --> Str) {
    '$' ~ @path.map({ '.' ~ $_ }).join;
  }

  method json-extract-text-sql(Str:D $col, @path --> Str) {
    "$col ->> '" ~ self.json-path-expr(@path) ~ "'";
  }

  method json-contains-sql(SqlStmt:D $stmt, Str:D $col, $data --> Str) {
    die "JSON containment is not supported on this adapter ({self.^name})";
  }

  method json-has-key-sql(SqlStmt:D $stmt, Str:D $col, Str:D $key --> Str) {
    die "JSON key-existence is not supported on this adapter ({self.^name})";
  }

  # Serialize a containment candidate: a Str is assumed to already be JSON.
  method json-literal($data --> Str) {
    $data ~~ Str ?? $data !! to-json($data);
  }

  method get-objects(Mu:U :$class, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock = False) {
    my @records = self.get-records(:@fields, :$table, :$join-table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock);
    my @objects;

    for @records.kv -> $k, $record {
      @objects.push: self!instantiate($class, $record, :@fields);
    }

    Notifications.notify('instantiation.active_record',
      { class-name => $class.^name, record-count => @objects.elems });

    @objects;
  }

  method !instantiate(Mu:U $class, %record, :@fields) {
    $class.^can('instantiate-record')
      ?? $class.instantiate-record(%record, :@fields)
      !! $class.new(id => %record{'id'}, record => { attrs => %record, :@fields });
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock = False) {
    my $record = self.get-record(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock);
    return Nil unless $record && $record{'id'};
    self!instantiate($class, $record, :@fields);
  }

  method !types-from-fields(Mu:D $obj) {
    my %types;
    for $obj.fields -> $f { %types{$f.name} = $f.type }
    %types;
  }

  method update-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs-to-persist;
    my %types = self!types-from-fields($obj);

    my $stmt = $obj.WHAT.default-id-locating
      ?? self.build-update(:$table, :%attrs, :%types, :id($obj.id))
      !! self.build-update-where(:$table, :%attrs, :%types, :where($obj.primary-key-where));

    self.exec-stmt($stmt);
  }

  method get-rows(Str:D :$sql) {
    self.exec($sql);
  }

  method get-records(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock = False) {
    my @records;
    my $stmt = self.build-select(:@fields, :$join-table, :$table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock);

    for self.exec-stmt($stmt).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field {
        %record{$field.name} = self.coerce-read($row[$kk], type => $field.type);
      }
      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where, :%where-not, :@or-groups, :@order, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock = False) {
    my $stmt = self.build-select(:@fields, :$table, :%where, :%where-not, :@or-groups, :@order, limit => 1, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints, :$lock);
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
}
