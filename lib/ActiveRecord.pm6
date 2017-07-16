
use v6.c;
use ActiveRecord::DB;
use ActiveRecord::Many;

class ActiveRecord {

    has $!db;
    #has Str @!table-names;
	has Str @!fields;
	has Int $!id;
	has Str @!has-manys;
	has Str @!belongs-tos;
	has %!attributes;

    submethod BUILD(:$!id) {
		$!db = ActiveRecord::DB.new;
	
		self.get-fields;
		self.get-attributes;

		@!has-manys = [];
		@!belongs-tos = [];

		say %!attributes;

		# self.get-table-names;
		# say @!table-names;
        # $!db.dispose;
    }

    method FALLBACK($name, *@rest) {
		# say "FALLBACK";
		# say "self.WHAT.perl: {self.WHAT.perl}";
		# say "\$name: $name";
		# say "\@rest: @rest[]";
		# say "end FALLBACK";

		return %!attributes{$name} if %!attributes{$name};		
    }

    method belongs-to($key) {
		@!belongs-tos.push: $key; 
    }

    method has-many($key) {
		@!has-manys.push: $key;
    }

	method table-name {
		self.WHAT.perl.lc ~ 's';
	}

    method find(*@rest) {
		my Int $id = 0;
		$id = @rest[0] if @rest.elems == 1 && @rest[0].isa(Int);
		return self.new(id => $id);
    }

	method get-attributes {
		%!attributes = $!db.get-record(fields => @!fields, table => self.table-name, where => id => $!id);
	}

    method get-fields {
		my $sql = $!db.build-sql(
	   		fields => qw<column_name>.words,
	    	table  => 'information_schema.columns',
	    	where  => {
				'table_schema' => 'public',
				'table_name'   => self.table-name
			},
	    	order  => qw<table_name>.words
		);
		@!fields = $!db.get-list(sql => $sql);
    }

    # method get-table-names {
	# 	my $sql = $!db.build-sql(
	#    		fields => qw<table_name>.words,
	#     	table  => 'information_schema.tables',
	#     	where  => { 'table_schema' => 'public' },
	#     	order  => qw<table_name>.words
	# 	);
	# 	@!table-names = $!db.get-list(sql => $sql);
    # }
}
