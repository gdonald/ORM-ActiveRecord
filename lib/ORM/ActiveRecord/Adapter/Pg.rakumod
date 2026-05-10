
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

class PgAdapter does Adapter is export {
  has Str $.schema;
  has Str $!host;
  has Str $!database;
  has Str $!user;
  has Str $!password;

  has $!db;

  submethod BUILD(Str :$!schema, Str :$!host, Str :$!database, Str :$!user, Str :$!password) {
    self.connect;
  }

  submethod DESTROY {
    $!db.dispose if $!db.defined;
    $!db = Nil;
  }

  method connect() {
    return if $!db.defined;
    $!db = DBIish.connect('Pg', :$!schema, :$!host, :$!database, :$!user, :$!password);
  }

  method is-connected(--> Bool) {
    $!db.defined.so;
  }

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

  method !ensure-connected {
    self.connect unless $!db.defined;
  }

  method bind-placeholder(Int:D $n --> Str) {
    '$' ~ $n;
  }

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

  method begin    { self.exec('BEGIN') }
  method commit   { self.exec('COMMIT') }
  method rollback { self.exec('ROLLBACK') }

  method build-value-sets(SqlStmt:D $stmt, :%attrs) {
    my @values;
    for %attrs.keys {
      next if $_ ~~ 'id';
      next unless %attrs{$_}.defined;
      my $value = %attrs{$_} ?? %attrs{$_} !! '';
      @values.push: "$_ = " ~ $stmt.placeholder($value);
    }
    @values.join(', ');
  }

  method build-values-list(SqlStmt:D $stmt, :@values) {
    @values.map({ $stmt.placeholder($_ ?? $_ !! '') }).join(', ');
  }

  method build-update(Str:D :$table, Int:D :$id, :%attrs --> SqlStmt) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-value-sets($stmt, :%attrs);
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

  method build-insert(Str:D :$table, :%attrs --> SqlStmt) {
    my %fvs = self.without-excluded-fields(%attrs);
    my @keys = %fvs.keys.grep({ %fvs{$_}.defined });
    my $fields = @keys.join(', ');
    my @values = @keys.map({ %fvs{$_} });
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-values-list($stmt, :@values);

    $stmt.sql = qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
      RETURNING id
      SQL

    $stmt;
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
    my $limit_ = $limit ?? "LIMIT $limit" !! '';
    my $offset_ = $offset ?? "OFFSET $offset" !! '';
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
      $limit_
      $offset_
      SQL

    $stmt;
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

  method update-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my $id = $obj.id;
    my $stmt = self.build-update(:$table, :%attrs, :$id);

    self.exec-stmt($stmt);
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my $stmt = self.build-insert(:$table, :%attrs);

    self.exec-stmt($stmt)[0][0].Int; # insert id
  }

  method get-rows(Str:D :$sql) {
    self.exec($sql);
  }

  method get-records(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :%where-not, :@or-groups, :@order, Int:D :$limit=0, Int:D :$offset=0, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins) {
    my @records;
    my $stmt = self.build-select(:@fields, :$join-table, :$table, :%where, :%where-not, :@or-groups, :@order, :$limit, :$offset, :$distinct, :@group, :@having, :$from-source, :$from-alias, :@joins);

    for self.exec-stmt($stmt).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field { %record{@fields[$kk].name} = $row[$kk] }
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
    for @fields.kv -> $k, $field { %record{@fields[$k].name} = $row[$k] }

    %record;
  }

  method get-fields(Str:D :$table) {
    my $type = 'character varying';
    my $names = <column_name data_type>;
    my @fields = $names.map({ Field.new(:name($_), :$type) });

    my $stmt = self.build-select(
      :@fields,
      table => 'information_schema.columns',
      where => { 'table_schema' => 'public', 'table_name' => $table },
      order => <ordinal_position>.list,
    );

    self.exec-stmt($stmt);
  }

  method get-list(Str:D :$sql, Int:D :$col=0) {
    self.exec($sql);
  }

  method get-table-names {
    my @fields = <table_name>.map({ Field.new(:name($_), :type('character varying')) });
    my $stmt = self.build-select(
      :@fields,
      table => 'information_schema.tables',
      where => { 'table_schema' => 'public' },
      order => <table_name>.list,
    );

    self.exec-stmt($stmt).map({ $_[0] });
  }

  method delete-records(Str:D :$table, :%where, :%where-not) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $where-sql = self.build-where($stmt, %where, %where-not);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    $stmt.sql = qq:to/SQL/;
      WITH deleted AS (
        DELETE FROM $table
        $where-clause
        RETURNING *
      ) SELECT count(*)
        FROM deleted
      SQL

    self.exec-stmt($stmt)[0][0].Int; # count
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

    self.exec-stmt($stmt)[0][0].Int; # count
  }
}
