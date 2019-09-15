
use JSON::Tiny;
use DBIish;

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

  method build-update(Str:D :$table, Int:D :$id, :%attrs) {
    my $values = %attrs.keys.map({ "$_ = '%attrs{$_}'" }).join(', ');

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
    my $values = %fvs.values.map({ "'$_'" }).join(', ');

    qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
      RETURNING id
      SQL
  }

  method build-select(Str:D :$table, :@fields, :%where, :@order, Int:D :$limit=0) {
    my $select = @fields.join(', ');
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
      my $obj = $class.new(id => $record{'id'}, record => { attributes => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(Str:D :$table, Mu:U :$class, :@fields, :%where) {
    my $record = self.get-record(:@fields, :$table, :%where);
    $class.new(id => $record{'id'}, record => { attributes => $record, :@fields });
  }

  method update-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attributes;
    my $id = $obj.id;
    my $sql = self.build-update(:$table, :%attrs, :$id);

    Log.sql(:$sql);
    my $query = $!db.prepare($sql);
    $query.execute;
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attributes;
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
      for @fields.kv -> $kk, $field {
        %record{@fields[$kk]} = $row[$kk];
      }

      @records.push: %record
    }

    @records;
  }

  method get-record(Str:D :$table, :@fields, :%where) {
    my $sql = self.build-select(:@fields, :$table, :%where, limit => 1);
    my $row = self.get-rows(:$sql)[0];
    my %record;

    for @fields.kv -> $k, $field {
      %record{@fields[$k]} = $row[$k];
    }

    %record;
  }

  method get-fields(Str:D :$table) {
    my $sql = self.build-select(
      fields => qw<column_name>.words,
      table => 'information_schema.columns',
      where => {
        'table_schema' => 'public',
        'table_name'   => $table
      },
      order => qw<table_name>.words
    );

    self.get-list(:$sql);
  }

  method get-list(Str:D :$sql, Int:D :$col=0) {
    self.get-rows(:$sql).map({ $_[$col] });
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
