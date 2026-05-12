
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Errors::Errors;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Relation::Query;
use ORM::ActiveRecord::Relation::Scope;
use ORM::ActiveRecord::Relation::Scopes;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Validations::Validator;
use ORM::ActiveRecord::Validations::Validators;

class Model is export {
  has DB $!db;
  has Errors $.errors;
  has Validators $.validators;

  has %.record is rw;
  has %.has-manys;
  has %.belongs-tos;

  has Int $.id;
  has @.fields of Field;
  has %.attrs;
  has %.attrs-db;
  has Bool $!readonly = False;

  has @.before-saves;
  has @.before-updates;
  has @.before-creates;

  has @.after-saves;
  has @.after-updates;
  has @.after-creates;

  has @.before-destroys;
  has @.after-destroys;

  my Scopes $.scopes;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD(Int:D :$!id, :%!record) {
    $!db = DB.shared;
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

  method is-readonly(--> Bool) {
    $!readonly;
  }

  method make-readonly {
    $!readonly = True;
    self;
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

  method before-destroy(Block $block) {
    @!before-destroys.push: $block;
  }

  method after-destroy(Block $block) {
    @!after-destroys.push: $block;
  }

  method do-before-destroys {
    for @!before-destroys { .() }
  }

  method do-after-destroys {
    for @!after-destroys { .() }
  }

  method table-name {
    self.WHAT.raku.lc ~ 's';
  }

  method fkey-name {
    self.WHAT.raku.lc ~ '_id';
  }

  method find(*@rest) {
    my Int $id = 0;
    $id = @rest[0] if @rest.elems == 1 && @rest[0].isa(Int);
    my $obj = self.new(:$id);
    die X::RecordNotFound.new(:model(self.WHAT.^name), :$id)
      unless $obj.attrs<id>;
    $obj;
  }

  method find-by(Hash:D $params) {
    self.where($params).first;
  }

  method find-by-or-die(Hash:D $params) {
    my $obj = self.find-by($params);
    die X::RecordNotFound.new(:model(self.WHAT.^name)) without $obj;
    $obj;
  }

  method sole {
    self.all.sole;
  }

  method find-sole-by(Hash:D $params) {
    self.where($params).sole;
  }

  method find-or-create-by(Hash:D $params) {
    self.all.find-or-create-by($params);
  }

  method find-or-create-by-or-die(Hash:D $params) {
    self.all.find-or-create-by-or-die($params);
  }

  method find-or-initialize-by(Hash:D $params) {
    self.all.find-or-initialize-by($params);
  }

  method create-with(Hash:D $attrs) {
    self.all.create-with($attrs);
  }

  multi method first {
    self.all.first;
  }

  multi method first(Int:D $n) {
    self.all.first($n);
  }

  multi method last {
    self.all.last;
  }

  multi method last(Int:D $n) {
    self.all.last($n);
  }

  method take(Int:D $limit = 1) {
    my $table = Utils.table-name(self);
    my @fields = DB.shared.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %where;
    DB.shared.get-objects(:$table, class => self.WHAT, :@fields, :%where, :$limit);
  }

  multi method exists(Hash:D $params) {
    self.where($params).count > 0;
  }

  multi method exists {
    self.count > 0;
  }

  method init-attrs {
    for @!fields {
      my $name = $_.name;
      next if $name eq 'id';
      given .type {
        when /integer/ { %!attrs{$name} = 0 }
        when /(character|text)/ { %!attrs{$name} = '' }
        when /boolean/ { %!attrs{$name} = False }
        when /timestamp|^date|^time/ { %!attrs{$name} = DateTime }
        default { say 'Unknown field type: ' ~ .type; die; }
      }
    }
  }

  method touch-timestamps {
    my $now = DateTime.now;
    for @!fields -> $field {
      given $field.name {
        when 'updated_at' { %!attrs<updated_at> = $now }
        when 'created_at' { %!attrs<created_at> = $now if $!id == 0 }
      }
    }
  }

  method merge-attrs(Hash:D $attrs) {
    for $attrs.keys { %!attrs«$_» = $attrs«$_» }
  }

  method get-attrs(:$id) {
    my @fields = @!fields;
    %!attrs = $!db.get-record(:@fields, table => self.table-name, where => :$id);
  }

  method field-names {
    @!fields.map({ $_.name });
  }

  method update-db-attrs {
    for %!attrs.keys { %!attrs-db«$_» = %!attrs«$_» }
  }

  method save {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!readonly;
    if self.is-valid {
      self.update-foreign-keys;
      self.do-before-saves;
      self.touch-timestamps;

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

  method save-or-die {
    self.save or self.raise-invalid;
    self;
  }

  method update-or-die(%attrs) {
    self.update(%attrs) or self.raise-invalid;
    self;
  }

  method raise-invalid {
    my @messages;
    for $!errors.errors -> $e {
      @messages.push: $e.field.name ~ ' ' ~ $e.message;
    }
    die X::RecordInvalid.new(:record(self), :@messages);
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

  multi method create-or-die(%attrs) {
    my %record = 'attrs' => %attrs;
    my $obj = self.new(:id(0), :%record);
    $obj.save-or-die;
    $obj;
  }

  multi method create-or-die {
    self.create-or-die({});
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
    DB.shared.count-records(:$table, :%where);
  }

  multi method count(Hash:D $params) {
    my $table = Utils.table-name(self);
    my %where = $params;
    DB.shared.count-records(:$table, :%where);
  }

  multi method count(Str:D $col) {
    self.all.count($col);
  }

  method sum($col)     { self.all.sum($col)     }
  method average($col) { self.all.average($col) }
  method minimum($col) { self.all.minimum($col) }
  method maximum($col) { self.all.maximum($col) }

  method calculate(Str:D $op, $col?) {
    self.all.calculate($op, $col);
  }

  method destroy {
    return False unless $!id;
    self.do-before-destroys;
    self.delete;
    self.do-after-destroys;
    True;
  }

  method delete {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!readonly;
    return False unless $!id;
    my $table = Utils.table-name(self);
    my %where = id => $!id;
    $!db.delete-records(:$table, :%where);
    $!id = 0;
    %!attrs<id> = 0;
    True;
  }

  method destroy-all {
    my $table = Utils.table-name(self);
    my %where;
    DB.shared.delete-records(:$table, :%where);
  }

  method where(Hash:D $params = {}) {
    my $class = self;
    Query.new(:$class, :$params);
  }

  method all {
    my $class = self;
    my %params;
    Query.new(:$class, :params(%params));
  }

  method none {
    self.all.none;
  }

  method order(*@cols, *%kw) {
    self.all.order(|@cols, |%kw);
  }

  method reorder(*@cols, *%kw) {
    self.all.reorder(|@cols, |%kw);
  }

  method in-order-of($col, @values) {
    self.all.in-order-of($col, @values);
  }

  method limit(Int:D $n) {
    self.all.limit($n);
  }

  method offset(Int:D $n) {
    self.all.offset($n);
  }

  method select(*@cols) {
    self.all.select(|@cols);
  }

  method distinct(Bool:D $on = True) {
    self.all.distinct($on);
  }

  method group(*@cols) {
    self.all.group(|@cols);
  }

  method regroup(*@cols) {
    self.all.regroup(|@cols);
  }

  method from($source, Str $alias?) {
    self.all.from($source, $alias);
  }

  method references(*@names) {
    self.all.references(|@names);
  }

  method readonly(Bool:D $on = True) {
    self.all.readonly($on);
  }

  method extending(*@roles) {
    self.all.extending(|@roles);
  }

  method having(*@parts) {
    self.all.having(|@parts);
  }

  method joins(*@args, *%kw) {
    self.all.joins(|@args, |%kw);
  }

  method left-outer-joins(*@args, *%kw) {
    self.all.left-outer-joins(|@args, |%kw);
  }

  method pluck(*@cols) {
    self.all.pluck(|@cols);
  }

  method ids {
    self.all.ids;
  }

  method pick(*@cols) {
    self.all.pick(|@cols);
  }

  method merge(Query:D $other) {
    self.all.merge($other);
  }

  method excluding(*@records) {
    self.all.excluding(|@records);
  }

  method missing(*@names, *%kw) {
    self.all.missing(|@names, |%kw);
  }

  method associated(*@names, *%kw) {
    self.all.associated(|@names, |%kw);
  }

  method find-each(Int:D :$batch-size = 1000) {
    self.all.find-each(:$batch-size);
  }

  method find-in-batches(Int:D :$batch-size = 1000) {
    self.all.find-in-batches(:$batch-size);
  }

  method in-batches(Int:D :$of = 1000, Bool:D :$load = False) {
    self.all.in-batches(:$of, :$load);
  }

  method with(*%kw) {
    self.all.with(|%kw);
  }

  method with-recursive(*%kw) {
    self.all.with-recursive(|%kw);
  }

  method annotate(*@comments) {
    self.all.annotate(|@comments);
  }

  method optimizer-hints(*@hints) {
    self.all.optimizer-hints(|@hints);
  }

  method to-sql(--> Str) {
    self.all.to-sql;
  }

  method explain(--> Str) {
    self.all.explain;
  }

  method is-any(--> Bool)   { self.all.is-any   }
  method is-empty(--> Bool) { self.all.is-empty }
  method is-none(--> Bool)  { self.all.is-none  }
  method is-one(--> Bool)   { self.all.is-one   }
  method is-many(--> Bool)  { self.all.is-many  }

  method cache-key(--> Str)              { self.all.cache-key              }
  method cache-version(--> Str)          { self.all.cache-version          }
  method cache-key-with-version(--> Str) { self.all.cache-key-with-version }

  multi method find-by-sql(@parts) {
    self!do-find-by-sql(@parts);
  }

  multi method find-by-sql(Str:D $sql, *@binds) {
    self!do-find-by-sql([$sql, |@binds]);
  }

  method !do-find-by-sql(@parts) {
    my $stmt = DB.shared.sanitize-sql(@parts);
    my @rows = DB.shared.exec-stmt-hash($stmt);
    my $table = Utils.table-name(self);
    my @fields = DB.shared.get-fields(:$table).map({ Field.new(:name($_[0]), :type($_[1])) });
    my %field-types = @fields.map({ .name => .type });

    my @objects;
    for @rows -> %row {
      my %attrs;
      for %row.kv -> $k, $v {
        if %field-types{$k}:exists {
          %attrs{$k} = DB.shared.coerce-read($v, type => %field-types{$k});
        } else {
          %attrs{$k} = $v;
        }
      }
      my $id = (%attrs<id> // 0).Int;
      my $obj = self.new(:$id, :record({ attrs => %attrs }));
      @objects.push: $obj;
    }
    @objects;
  }

  multi method select-all(@parts) {
    self!do-select-all(@parts);
  }

  multi method select-all(Str:D $sql, *@binds) {
    self!do-select-all([$sql, |@binds]);
  }

  method !do-select-all(@parts) {
    my $stmt = DB.shared.sanitize-sql(@parts);
    DB.shared.exec-stmt-hash($stmt);
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
