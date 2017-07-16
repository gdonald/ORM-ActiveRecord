
use v6.c;
use JSON::Tiny;
use DBIish;

class ActiveRecord::DB {

    has Str $!database;
    has Str $!user;
    has Str $!password;

    has $!db;
    has @!rows;

    submethod BUILD {
        self.get-config;
        self.connect-db;
        # $!db.dispose;
    }

    method build-sql(:@fields, :$table, :%where, :@order, :$limit) {
	    my $select = @fields.join(',');
	    my @where = [];
	    for %where.kv -> $k, $v {
	        @where.push: "$k = '$v'";
	    }
        my $where = @where.join(" AND ");
	    my $order = @order ?? "ORDER BY @order.join(',')" !! '';
        my $limit_ = $limit ?? "LIMIT $limit" !! '';

	    my Str $sql = qq:to/SQL/;
            SELECT $select
	        FROM $table
	        WHERE $where
            $order
            $limit_
            SQL

        #say "\$sql: $sql";

	    return $sql;
    }
    
    method get-rows(:$sql) {
        my $query = $!db.prepare(qq:to/SQL/);
            $sql
            SQL
        $query.execute();
        return $query.allrows();
    }

    method get-record(:@fields, :$table, :%where) {
        my $sql = self.build-sql(
	   		fields => @fields,
	    	table  => $table,
	    	where  => %where,
	    	limit  => 1
		);
		my $row = self.get-rows(sql => $sql)[0];
        my %record;
        for @fields.kv -> $k, $field {
            %record{@fields[$k]} = $row[$k];
        }
        return %record;
    }

    method get-list(:$sql, :$col=0) {
	    my @list = [];
	    my @rows = self.get-rows(sql => $sql);
        if @rows.elems > 0 {
	        for @rows -> $row {
		        @list.push: $row[$col];
            }
        }
	    return @list;
    }
    
    method connect-db {
        return if $!db.defined;
        $!db = DBIish.connect('Pg', :$!database, :$!user, :$!password);
    }

    method get-config {
        if (my $fh = open 'config/application.json', :r) {
            my $contents = $fh.slurp-rest;
            $fh.close;

            my $json = from-json($contents);
            $!database = $json{'db'}{'name'};
            $!user     = $json{'db'}{'user'};
            $!password = $json{'db'}{'password'};
        }
    }
}
