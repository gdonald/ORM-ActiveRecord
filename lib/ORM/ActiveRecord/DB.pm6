
use JSON::Tiny;
use DBIish;

use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Log;
use ORM::ActiveRecord::Utils;

class DB is export {
  has Str $.schema;
  has Str $!database;
  has Str $!user;
  has Str $!password;

  has $!db;
  has @!rows;

  submethod BUILD {
    self.get-config;
    self.connect-db;
  }

  submethod DESTROY {
    $!db.dispose;
    $!db = Nil;
  }

  method begin {
    my $sql = 'BEGIN';
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
  }

  method commit {
    my $sql = 'COMMIT';
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
  }

  method exec(Str:D $sql) {
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
    $query.allrows;
  }

  method build-value-sets(:%attrs) {
    my @values;

    for %attrs.keys {
      next if $_ ~~ 'id';
      my $value = %attrs{$_} ?? %attrs{$_} !! '';
      @values.push: "$_ = '$value'";
    }

    @values.join(', ');
  }

  method build-values-list(:@values) {
    @values.map({ $_ ?? "'$_'" !! "''" }).join(', ');
  }

  method build-update(Str:D :$table, Int:D :$id, :%attrs) {
    my $values = self.build-value-sets(:%attrs);

    qq:to/SQL/;
      UPDATE $table
      SET $values
      WHERE id = $id
      SQL
  }

  method without-excluded-fields(%attrs) {
    for %attrs.keys { %attrs{$_}:delete if $_ ~~ /_confirmation$/ }
    %attrs;
  }

  method build-insert(Str:D :$table, :%attrs) {
    my %fvs = self.without-excluded-fields(%attrs);
    my $fields = %fvs.keys.join(', ');
    my @values = %fvs.values;
    my $values = self.build-values-list(:@values);

    qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
      RETURNING id
      SQL
  }

  method build-select(Str:D :$table, :@fields, :%where, :@order, Int:D :$limit=0) {
    my $select = @fields.map({ $_.name }).join(', ');
    my $where = self.build-where(%where);
    my $order = @order ?? "ORDER BY @order.join(', ')" !! '';
    my $limit_ = $limit ?? "LIMIT $limit" !! '';

    qq:to/SQL/;
      SELECT $select
	    FROM $table
	    WHERE $where
      $order
      $limit_
      SQL
  }

  method build-where(%where) {
    %where.keys.map({ "$_ = '%where{$_}'" }).join(' AND ');
  }

  method get-objects(Str:D :$table, Mu:U :$class, :@fields, :%where) {
    my @records = self.get-records(:@fields, :$table, :%where);
    my @objects;

    for @records.kv -> $k, $record {
      my $obj = $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where) {
    my $record = self.get-record(:@fields, :$table, :%where);
    $class.new(id => $record{'id'}, record => { attrs => $record, :@fields });
  }

  method update-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my $id = $obj.id;
    my $sql = self.build-update(:$table, :%attrs, :$id);

    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my $sql = self.build-insert(:$table, :%attrs);

    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
    $query.allrows[0][0].Int; # insert id
  }

  method get-rows(Str:D :$sql) {
    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
    $query.allrows;
  }

  method get-records(Str:D :$table, :@fields, :%where) {
    my @records;
    my $sql = self.build-select(:@fields, :$table, :%where);

    for self.get-rows(:$sql).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field { %record{@fields[$kk].name} = $row[$kk] }
      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where) {
    my $sql = self.build-select(:@fields, :$table, :%where, limit => 1);
    my $row = self.get-rows(:$sql)[0];
    my %record;
    for @fields.kv -> $k, $field { %record{@fields[$k].name} = $row[$k] }

    %record;
  }

  method get-fields(Str:D :$table) {
    my $type = 'character varying';
    my $names = <column_name data_type>;
    my @fields = $names.map({ Field.new(:name($_), :$type) });

    my $sql = self.build-select(
      :@fields,
      table => 'information_schema.columns',
      where => { 'table_schema' => 'public', 'table_name' => $table },
      order => qw<table_name>.words
    );

    self.get-rows(:$sql);
  }

  method get-list(Str:D :$sql, Int:D :$col=0) {
    self.get-rows(:$sql);
  }

  method get-table-names {
    my $sql = $!db.build-select(
      fields => qw<table_name>.words,
      table  => 'information_schema.tables',
      where  => { 'table_schema' => 'public' },
      order  => qw<table_name>.word
    );

    $!db.get-list(:$sql);
  }

  method delete-records(Str:D :$table, :%where) {
    my $where = self.build-where(%where);

    my $sql = qq:to/SQL/;
      WITH deleted AS (
        DELETE FROM $table
        WHERE $where
        RETURNING *
      ) SELECT count(*)
        FROM deleted
      SQL

    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
    $query.allrows[0][0].Int; # count
  }

  method count-records(Str:D :$table, :%where) {
    my $where = self.build-where(%where);
    $where = $where ?? " WHERE $where" !! '';

    my $sql = qq:to/SQL/;
      SELECT count(*)
      FROM $table
      $where
      SQL

    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
    $query.allrows[0][0].Int; # count
  }

  method connect-db {
    return if $!db.defined;
    $!db = DBIish.connect('Pg', :$!schema, :$!database, :$!user, :$!password);
  }

  method get-config {
    if (my $fh = open 'config/application.json', :r) {
      my $contents = $fh.slurp-rest;
      $fh.close;

      my $json = from-json($contents);
      $!schema   = $json{'db'}{'schema'};
      $!database = $json{'db'}{'name'};
      $!user     = $json{'db'}{'user'};
      $!password = $json{'db'}{'password'};
    }
  }
}
