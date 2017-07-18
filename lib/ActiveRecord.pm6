
use v6.c;
use ActiveRecord::DB;

class ActiveRecord {

    has $!db;
    has Str @!fields;
    has Int $!id;
    has Str @!has-manys;
    has Str @!belongs-tos;
    has %!attributes;

    submethod BUILD(:$!id) {
	$!db = ActiveRecord::DB.new;
	@!fields = $!db.get-fields(table => self.table-name);

	self.get-attributes;

	@!has-manys = [];
	@!belongs-tos = [];

	say %!attributes;
        # $!db.dispose;
    }

    method FALLBACK($name, *@rest) {
	# say "FALLBACK";
	# say "self.WHAT.perl: {self.WHAT.perl}";
	# say "\$name: $name";
	# say "\@rest: @rest[]";
	# say "end FALLBACK";

	return %!attributes{$name} if %!attributes{$name};

	if any(@!has-manys) eq $name {
	    # say "{self.WHAT.perl.lc} has many {$name}";
	    my @fields = $!db.get-fields(table => $name);
	    return $!db.get-records(fields => @fields, table => $name, where => self.fkey-name => $!id);
	}
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

    method fkey-name {
	self.WHAT.perl.lc ~ '_id';
    }

    method find(*@rest) {
	my Int $id = 0;
	$id = @rest[0] if @rest.elems == 1 && @rest[0].isa(Int);
	return self.new(id => $id);
    }

    method get-attributes {
	%!attributes = $!db.get-record(fields => @!fields, table => self.table-name, where => id => $!id);
    }
}
