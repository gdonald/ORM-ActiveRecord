
use JSON::Tiny;
use DBIish;

use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Log;
use ORM::ActiveRecord::Utils;

class SqlStmt is export {
  has Str $.sql is rw = '';
  has @.binds is rw;

  method placeholder($value --> Str) {
    @!binds.push($value);
    '$' ~ @!binds.elems;
  }
}

class DB is export {
  my DB $shared;

  has Str $.schema;
  has Str $!host;
  has Str $!database;
  has Str $!user;
  has Str $!password;

  has $!db;
  has @!rows;

  submethod BUILD {
    self.get-config;
    self.connect-db;
  }

  # Process-wide shared connection. Use this everywhere instead of `DB.new` —
  # creating an anonymous DB per call relies on GC-driven `dispose`, which
  # races with in-flight `allrows` iteration in DBDish::Pg and produces
  # "No such method 'PQgetisnull' for invocant of type 'Any'" errors.
  method shared(--> DB) {
    $shared //= DB.new;
    $shared;
  }

  submethod DESTROY {
    $!db.dispose if $!db.defined;
    $!db = Nil;
  }

  method begin {
    self.exec('BEGIN');
  }

  method commit {
    self.exec('COMMIT');
  }

  method rollback {
    self.exec('ROLLBACK');
  }

  method exec(Str:D $sql, *@binds) {
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute(|@binds);
    $query.allrows;
  }

  method exec-stmt(SqlStmt:D $stmt) {
    Log.sql(:sql($stmt.sql));
    my $query = $!db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    $query.allrows;
  }

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
    my $stmt = SqlStmt.new;
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
    my $stmt = SqlStmt.new;
    my $values = self.build-values-list($stmt, :@values);

    $stmt.sql = qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
      RETURNING id
      SQL

    $stmt;
  }

  method build-select(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :@order, Int:D :$limit=0, Int:D :$offset=0 --> SqlStmt) {
    my $stmt = SqlStmt.new;
    my $select = @fields.map({ $table ~ '.' ~ $_.name }).join(', ');
    my $where-sql = self.build-where($stmt, %where);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    my $order = @order ?? "ORDER BY @order.join(', ')" !! '';
    my $limit_ = $limit ?? "LIMIT $limit" !! '';
    my $offset_ = $offset ?? "OFFSET $offset" !! '';
    my $join = '';

    if $join-table {
      my $foreign-key = Utils.to-foreign-key($table);

      $join = qq:to/SQL/;
        LEFT JOIN $join-table
        ON $table.id = $join-table.$foreign-key
      SQL
    }

    $stmt.sql = qq:to/SQL/;
      SELECT $select
	    FROM $table
      $join
      $where-clause
      $order
      $limit_
      $offset_
      SQL

    $stmt;
  }

  method build-where(SqlStmt:D $stmt, %where --> Str) {
    return '' unless %where.elems;
    %where.keys.map({ "$_ = " ~ $stmt.placeholder(%where{$_}) }).join(' AND ');
  }

  method get-objects(Mu:U :$class, Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :@order, Int:D :$limit=0, Int:D :$offset=0) {
    my @records = self.get-records(:@fields, :$table, :$join-table, :%where, :@order, :$limit, :$offset);
    my @objects;

    for @records.kv -> $k, $record {
      my $obj = $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where, :@order) {
    my $record = self.get-record(:@fields, :$table, :%where, :@order);
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

  method get-records(Str:D :$table, Str:D :$join-table = '', :@fields, :%where, :@order, Int:D :$limit=0, Int:D :$offset=0) {
    my @records;
    my $stmt = self.build-select(:@fields, :$join-table, :$table, :%where, :@order, :$limit, :$offset);

    for self.exec-stmt($stmt).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field { %record{@fields[$kk].name} = $row[$kk] }
      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where, :@order) {
    my $stmt = self.build-select(:@fields, :$table, :%where, :@order, limit => 1);
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

  method delete-records(Str:D :$table, :%where) {
    my $stmt = SqlStmt.new;
    my $where-sql = self.build-where($stmt, %where);
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

  method count-records(Str:D :$table, :%where) {
    my $stmt = SqlStmt.new;
    my $where-sql = self.build-where($stmt, %where);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    $stmt.sql = qq:to/SQL/;
      SELECT count(*)
      FROM $table
      $where-clause
      SQL

    self.exec-stmt($stmt)[0][0].Int; # count
  }

  method connect-db {
    return if $!db.defined;

    $!db = DBIish.connect('Pg', :$!schema, :$!host, :$!database, :$!user, :$!password);
  }

  method get-config {
    if (my $fh = open 'config/application.json', :r) {
      my $contents = $fh.slurp-rest;
      $fh.close;

      my $json = from-json($contents);
      $!schema   = $json{'db'}{'schema'};
      $!host     = $json{'db'}{'host'};
      $!database = $json{'db'}{'name'};
      $!user     = $json{'db'}{'user'};
      $!password = $json{'db'}{'password'};
    }
  }
}
