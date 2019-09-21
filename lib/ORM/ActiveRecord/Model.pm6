
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Errors;
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Utils;
use ORM::ActiveRecord::Validator;
use ORM::ActiveRecord::Validators;

class Model is export {
  has DB $!db;
  has Errors $.errors;
  has Validators $.validators;

  has %.record is rw;
  has %!has-manys;
  has %.belongs-tos;

  has Int $.id;
  has @.fields of Field;
  has %.attrs is rw;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD(Int:D :$!id, :%!record) {
    $!db = DB.new;
    $!errors = Errors.new;
    $!validators = Validators.new;

    if %!record {
      @!fields = %!record{'fields'} ?? slip(%!record{'fields'}) !! self.get-fields(self.table-name);
      %!attrs = %!record{'attrs'} ?? %!record{'attrs'} !! self.init-attrs;
    } elsif $!id {
      @!fields = self.get-fields(self.table-name);
      self.get-attrs(:$!id);
    }
  }

  method FALLBACK(Str:D $name, *@rest) is raw {
    return-rw %!attrs{$name} if %!attrs«$name»:exists;

    if any(%!has-manys.keys) eq $name {
      my $fkey-name = Utils.base-name(self.fkey-name);
      my @fields = self.get-fields($name);
      return $!db.get-objects(class => %!has-manys{$name}{'class'}, :@fields, table => $name, where => $fkey-name => $!id);
    }

    if any(%!belongs-tos.keys) eq $name {
      my Str $table = $name ~ 's';
      my Int $id = %!attrs{$name ~ '_id'};
      my @fields = self.get-fields($table);
      return $!db.get-object(class => %!belongs-tos{$name}{'class'}, :@fields, :$table, where => :$id);
    }
  }

  method get-fields(Str:D $table) {
    $!db.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
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

  method init-attrs {
    my %attrs;

    for @!fields -> $field {
      next if $field.name eq 'id';
      given $field.type {
        when /integer/ { %attrs{$field.name} = 0; }
        when /character/ { %attrs{$field.name} = ''; }
        default { say 'Unknown field type'; die; }
      }
    }

    %attrs;
  }

  method get-attrs(:$id) {
    my @fields = self.field-names;
    %!attrs = $!db.get-record(:@fields, table => self.table-name, where => :$id);
  }

  method field-names {
    @!fields.map({ $_.name });
  }

  method save {
    if self.is-valid {
      self.update-foreign-keys;

      given $!id {
        when 0 { $!id = $!db.create-object(self) }
        default { $!db.update-object(self) }
      }
      return True;
    }
    False;
  }

  method update-foreign-keys {
    for $.belongs-tos.keys -> $key {
      next unless $.attrs{$key};
      if $.attrs{$key}.^name eq $.belongs-tos{$key}.value.^name {
        $.attrs{$key ~ '_id'} = $.attrs{$key}.id;
        $.attrs{$key}:delete;
      }
    }
  }

  method update(%attrs) {
    for %attrs.keys -> $key {
      %!attrs{$key} = %attrs{$key};
    }
    self.save;
  }

  multi method create(%attrs) {
    my %record = 'attrs' => %attrs;
    my $obj = self.new(:id(0), :%record);
    $obj.save if $obj.is-valid;
    $obj;
  }

  multi method create {
    self.create({});
  }

  multi method build(%attrs) {
    my %record = 'attrs' => %attrs;
    self.new(:id(0), :%record);
  }

  multi method build {
    self.build({});
  }

  method is-valid {
    !self.is-invalid;
  }

  method is-invalid {
    $!errors = Errors.new;
    $!validators.validate($!db, self);
    $!errors.errors.elems.so;
  }

  method validate(Str:D $field_name, Hash:D $params) {
    my $klass = self.WHAT;
    my $field = self.get-field($field_name);
    my $v = Validator.new(:$klass, :$field, :$params);
    $!validators.validators.push($v);
  }

  method get-field(Str:D $name) {
    for self.fields { return $_ if .name ~~ $name }
  }

  method destroy-all {
    my $table = Utils.table-name(self);
    my %where = '1' => '1';
    DB.new.delete-records(:$table, :%where);
  }
}
