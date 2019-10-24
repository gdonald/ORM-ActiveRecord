
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Errors;
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Scope;
use ORM::ActiveRecord::Scopes;
use ORM::ActiveRecord::Utils;
use ORM::ActiveRecord::Validator;
use ORM::ActiveRecord::Validators;
use ORM::ActiveRecord::Query;

class Model is export {
  has DB $!db;
  has Errors $.errors;
  has Validators $.validators;

  has %.record is rw;
  has %!has-manys;
  has %.belongs-tos;

  has Int $.id;
  has @.fields of Field;
  has %.attrs;
  has %.attrs-db;

  has @.before-saves;
  has @.before-updates;
  has @.before-creates;

  has @.after-saves;
  has @.after-updates;
  has @.after-creates;

  my Scopes $.scopes;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD(Int:D :$!id, :%!record) {
    $!db = DB.new;
    $!errors = Errors.new;
    $!validators = Validators.new;

    @!fields = self.get-fields(self.table-name);
    self.init-attrs;

    if %!record && %!record<attrs> {
      self.merge-attrs(%!record<attrs>);
    } elsif $!id {
      self.get-attrs(:$!id);
    }
  }

  method FALLBACK(Str:D $name, *@rest) is raw {
    if $?CLASS.scopes.exists($name) {
      return $?CLASS.scopes.exec($name);
    }

    if $name ~~ /_id$/ && %!attrs«$name» == 0 {
      my $base-name = $name.subst(/_id$/, '');
      return self."$base-name"().id;
    }

    return-rw %!attrs«$name» if %!attrs«$name»:exists;

    if any(%!has-manys.keys) eq $name {
      my $fkey-name = Utils.base-name(self.fkey-name);
      my @fields = self.get-fields($name);
      my $class = Mu:U;
      my $join-table = '';

      for %!has-manys{$name}.keys -> $key {
        given $key {
          when 'class' { $class = %!has-manys{$name}{'class'} }
          when 'through' {
            $join-table = %!has-manys{$name}{'through'}.key;
            $class = self.get-through-class($name, $join-table);
          }
          default { say 'Unknown has-many type ' ~ %!has-manys{$name}; die }
        }
      }

      return $!db.get-objects(:$class, :@fields, :table($name), :$join-table, :where($fkey-name => $!id));
    }

    if any(%!belongs-tos.keys) eq $name {
      my Str $table = $name ~ 's';
      my Int $id = %!attrs{$name ~ '_id'};
      my @fields = self.get-fields($table);
      return $!db.get-object(class => %!belongs-tos{$name}{'class'}, :@fields, :$table, where => :$id);
    }

    return if $name ~~ /_confirmation/;

    say 'Unknown attribute or method "' ~ $name ~ '"'; die;
  }

  method get-through-class(Str:D $name, Str:D $join-table) {
    my $class = %!has-manys{$join-table}{'class'};
    my $singular = Utils.singular($name);

    $class.new(:id(0)).belongs-tos{$singular}{'class'};
  }

  method is-dirty(--> Bool) {
    for %!attrs.keys -> $key { return True if %!attrs«$key» !~~ %!attrs-db«$key» }
    False;
  }

  method belongs-to(*%rest) {
    %!belongs-tos.push: %rest.keys.first => %rest.values.first;
  }

  method has-many(*%rest) {
    %!has-manys.push: %rest.keys.first => %rest.values.first;
  }

  method before-save(Block $block) {
    @!before-saves.push: $block;
  }

  method before-update(Block $block) {
    @!before-updates.push: $block;
  }

  method before-create(Block $block) {
    @!before-creates.push: $block;
  }

  method after-save(Block $block) {
    @!after-saves.push: $block;
  }

  method after-update(Block $block) {
    @!after-updates.push: $block;
  }

  method after-create(Block $block) {
    @!after-creates.push: $block;
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
    for @!fields {
      my $name = $_.name;
      next if $name eq 'id';
      given .type {
        when /integer/ { %!attrs{$name} = 0 }
        when /(character|text)/ { %!attrs{$name} = '' }
        when /boolean/ { %!attrs{$name} = False }
        default { say 'Unknown field type: ' ~ .type; die; }
      }
    }
  }

  method merge-attrs(Hash:D $attrs) {
    for $attrs.keys { %!attrs«$_» = $attrs«$_» }
  }

  method get-attrs(:$id) {
    my @fields = self.field-names;
    %!attrs = $!db.get-record(:@fields, table => self.table-name, where => :$id);
  }

  method field-names {
    @!fields.map({ $_.name });
  }

  method update-db-attrs {
    for %!attrs.keys { %!attrs-db«$_» = %!attrs«$_» }
  }

  method save {
    if self.is-valid {
      self.update-foreign-keys;
      self.do-before-saves;

      given $!id {
        when 0 {
          self.do-before-creates;
          %!attrs<id> = $!id = $!db.create-object(self);
          self.do-after-creates;
        }
        default {
          self.do-before-updates;
          $!db.update-object(self);
          self.do-after-updates;
        }
      }

      self.do-after-saves;
      self.update-db-attrs;
      return True;
    }
    False;
  }

  method do-before-saves {
    for @!before-saves { .() }
  }

  method do-before-creates {
    for @!before-creates { .() }
  }

  method do-before-updates {
    for @!before-updates { .() }
  }

  method do-after-saves {
    for @!after-saves { .() }
  }

  method do-after-creates {
    for @!after-creates { .() }
  }

  method do-after-updates {
    for @!after-updates { .() }
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

  method validate(Str:D $name, Hash:D $params) {
    my $klass = self.WHAT;
    my $field = self.get-field($name);
    if $field !~~ Field { say 'Field "' ~ $name ~ '" does not exist'; die }

    my $v = Validator.new(:$klass, :$field, :$params);
    $!validators.validators.push($v);
  }

  method scope(Str:D $name, Block:D $block) {
    my $klass = self.WHAT;

    my $s = Scope.new(:$klass, :$name, :$block);
    $?CLASS.scopes.scopes.push($s);
  }

  method get-fields(Str:D $table) {
    $!db.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
  }

  method get-field(Str:D $name) {
    for self.fields { return $_ if .name ~~ $name }
    for self.fields { return $_ if .name ~~ $name ~ '_id' && .type ~~ 'integer' }
  }

  multi method count {
    my $table = Utils.table-name(self);
    my %where;
    DB.new.count-records(:$table, :%where);
  }

  multi method count(Hash:D $params) {
    my $table = Utils.table-name(self);
    my %where = $params;
    DB.new.count-records(:$table, :%where);
  }

  method destroy-all {
    my $table = Utils.table-name(self);
    my %where = '1' => '1';
    DB.new.delete-records(:$table, :%where);
  }

  method where(Hash:D $params) {
    my $class = self;
    Query.new(:$class, :$params);
  }
}

multi sub infix:<==>(Model $a, Model $b --> Bool) is export {
  my @keys = $a.attrs.keys;
  return False unless @keys.elems == $b.attrs.keys.elems;

  for @keys -> $k {
    given $a.attrs{$k} {
      when Numeric { return False unless $a.attrs{$k} == $b.attrs{$k} }
      when Str     { return False unless $a.attrs{$k} eq $b.attrs{$k} }
      default      { say 'Unknown type: ' ~ $a.attrs{$k}.^name; die }
    }
  }

  True;
}
