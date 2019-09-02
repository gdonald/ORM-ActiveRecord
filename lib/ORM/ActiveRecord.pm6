
unit module ORM::ActiveRecord;

use ORM::ActiveRecord::DB;

class ActiveRecord is export {
  has DB $!db;
  has %!record;
  has %!has-manys;
  has %!belongs-tos;

  has Int $.id;
  has Str @.fields;
  has %.attributes;

  submethod BUILD(:$!id, :%!record, :$action) {
    $!db = DB.new;

    if %!record && %!record{'attributes'} {
      %!attributes = %!record{'attributes'};
      if %!record{'fields'} {
        @!fields = slip(%!record{'fields'});
      } else {
        @!fields = $!db.get-fields(table => self.table-name);
      }
    } elsif $!id {
      @!fields = $!db.get-fields(table => self.table-name);
      self.get-attributes;
    }

    given $action {
      when 'create' { $!id = $!db.create-object(self) }
    }
  }

  method FALLBACK($name, *@rest) {
    return %!attributes{$name} if %!attributes{$name};

    if any(%!has-manys.keys) eq $name {
      my Str @fields = $!db.get-fields(table => $name);
      return $!db.get-objects(class => %!has-manys{$name}{'class'}, :@fields, table => $name, where => self.fkey-name => $!id);
    }

    if any(%!belongs-tos.keys) eq $name {
      my Str $table = $name ~ 's';
      my Str @fields = $!db.get-fields(:$table);
      my Int $id = %!attributes{$name ~ '_id'};
      return $!db.get-object(class => %!belongs-tos{$name}{'class'}, :@fields, :$table, where => :$id);
    }
  }

  method belongs-to(*%rest) {
    %!belongs-tos.push: %rest.keys.first => %rest.values.first;
  }

  method has-many(*%rest) {
    %!has-manys.push: %rest.keys.first => %rest.values.first;
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
    self.new(:$id);
  }

  method get-attributes {
    %!attributes = $!db.get-record(:@!fields, table => self.table-name, where => :$!id);
  }

  method create(%attributes) {
    my %record = 'attributes' => %attributes;
    my $action = 'create';
    self.new(:id(0), :%record, :$action);
  }
}
