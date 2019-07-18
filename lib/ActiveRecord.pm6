use v6.d;
use ActiveRecord::DB;

class ActiveRecord {
  has $!db;
  has Str @!fields;
  has Int $!id;
  has %!record;
  has %!has-manys;
  has %!belongs-tos;
  has %!attributes;

  submethod BUILD(:$!id, :%!record) {
    $!db = ActiveRecord::DB.new;

    if %!record && %!record{'attributes'} {
      %!attributes = %!record{'attributes'};
      @!fields = slip(%!record{'fields'}) if %!record{'fields'};
    } elsif $!id {
      @!fields = $!db.get-fields(table => self.table-name);
      self.get-attributes;
    }

    # $!db.dispose;
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
}
