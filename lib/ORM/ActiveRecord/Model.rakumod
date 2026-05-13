
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
use JSON::Tiny;

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
  has Bool $!destroyed = False;
  has Bool $!previously-new = False;
  has Bool $!previously-persisted = False;
  has %!previous-changes;
  has %!will-change;

  has @.before-saves;
  has @.before-updates;
  has @.before-creates;

  has @.after-saves;
  has @.after-updates;
  has @.after-creates;

  has @.before-destroys;
  has @.after-destroys;

  has @.filter-attributes;

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

    if $name ~~ /^ 'is-saved-change-to-' (.+) $/ {
      return self.is-saved-change-to(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ 'saved-change-to-' (.+) $/ {
      return self.saved-change-to(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ 'is-' (.+) '-changed' $/ {
      return self.is-attribute-changed(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ (.+) '-before-last-save' $/ {
      return self.attribute-before-last-save(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ (.+) '-will-change' $/ {
      return self.attribute-will-change(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ (.+) '-change' $/ {
      return self.attribute-change(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ (.+) '-was' $/ {
      return self.attribute-was(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ 'restore-' (.+) $/ {
      return self.restore-attribute(~$0) if self.has-attribute(~$0);
    }
    if $name ~~ /^ 'reset-' (.+) $/ {
      return self.reset-attribute(~$0) if self.has-attribute(~$0);
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
    for %!attrs.keys -> $key { return True if %!attrs«$key» !eqv %!attrs-db«$key» }
    False;
  }

  method is-changed(--> Bool) {
    return True if %!will-change.elems;
    for %!attrs.keys -> $key { return True if %!attrs«$key» !eqv %!attrs-db«$key» }
    False;
  }

  method changed() {
    my @names;
    for %!attrs.keys.sort -> $key {
      @names.push($key) if %!will-change{$key} || %!attrs«$key» !eqv %!attrs-db«$key»;
    }
    @names.list;
  }

  method changes(--> Hash) {
    my %h;
    for self.changed -> $name {
      %h{$name} = [%!attrs-db{$name}, %!attrs{$name}];
    }
    %h;
  }

  method changed-attributes(--> Hash) {
    my %h;
    for self.changed -> $name {
      %h{$name} = %!attrs-db{$name};
    }
    %h;
  }

  method previous-changes(--> Hash) {
    %!previous-changes.clone;
  }

  method is-attribute-changed(Str:D $name --> Bool) {
    so %!will-change{$name} || (%!attrs«$name» !eqv %!attrs-db«$name»);
  }

  method attribute-was(Str:D $name) {
    self.is-attribute-changed($name) ?? %!attrs-db{$name} !! %!attrs{$name};
  }

  method attribute-change(Str:D $name) {
    return Nil unless self.is-attribute-changed($name);
    [%!attrs-db{$name}, %!attrs{$name}];
  }

  method attribute-will-change(Str:D $name) {
    %!will-change{$name} = True;
    self;
  }

  method is-saved-change-to(Str:D $name --> Bool) {
    %!previous-changes{$name}:exists;
  }

  method saved-change-to(Str:D $name) {
    %!previous-changes{$name} // Nil;
  }

  method attribute-before-last-save(Str:D $name) {
    %!previous-changes{$name}:exists
      ?? %!previous-changes{$name}[0]
      !! %!attrs{$name};
  }

  method restore-attributes {
    die X::FrozenRecord.new(model => self.WHAT.^name) if $!destroyed;
    for %!attrs.keys -> $key {
      %!attrs{$key} = %!attrs-db{$key} if %!attrs-db{$key}:exists;
    }
    %!will-change = ();
    self;
  }

  method restore-attribute(Str:D $name) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if $!destroyed;
    %!attrs{$name} = %!attrs-db{$name} if %!attrs-db{$name}:exists;
    %!will-change{$name}:delete;
    self;
  }

  method reset-attribute(Str:D $name) {
    self.restore-attribute($name);
  }

  method reload {
    die X::FrozenRecord.new(model => self.WHAT.^name) if $!destroyed;
    return self if $!id == 0;
    self.get-attrs(:$!id);
    %!will-change = ();
    self;
  }

  method is-readonly(--> Bool) {
    $!readonly;
  }

  method make-readonly {
    $!readonly = True;
    self;
  }

  method is-new-record(--> Bool) {
    $!id == 0 && !$!destroyed;
  }

  method is-persisted(--> Bool) {
    $!id != 0 && !$!destroyed;
  }

  method is-destroyed(--> Bool) {
    $!destroyed;
  }

  method was-new-record(--> Bool) {
    $!previously-new;
  }

  method was-persisted(--> Bool) {
    $!previously-persisted;
  }

  method is-frozen(--> Bool) {
    $!destroyed;
  }

  method assign-attributes(%attrs) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if $!destroyed;
    for %attrs.kv -> $key, $val { %!attrs{$key} = $val }
    self;
  }

  method attributes() is rw {
    my $model = self;
    Proxy.new(
      FETCH => method () { %($model.attrs) },
      STORE => method ($new) {
        $model.assign-attributes($new);
        %($model.attrs);
      }
    );
  }

  method read-attribute(Str:D $name) {
    %!attrs{$name};
  }

  method write-attribute(Str:D $name, $value) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if $!destroyed;
    %!attrs{$name} = $value;
    $value;
  }

  method AT-KEY(Str:D $key) is rw {
    if $!destroyed {
      my $model = self;
      return Proxy.new(
        FETCH => method () { $model.attrs{$key} },
        STORE => method ($) {
          die X::FrozenRecord.new(model => $model.WHAT.^name);
        }
      );
    }
    %!attrs{$key};
  }

  method EXISTS-KEY(Str:D $key --> Bool) { %!attrs{$key}:exists }

  method has-attribute(Str:D $name --> Bool) {
    so @!fields.first({ .name eq $name });
  }

  method is-attribute-present(Str:D $name --> Bool) {
    return False unless %!attrs{$name}:exists;
    my $v = %!attrs{$name};
    return False without $v;
    return False if $v ~~ Bool && !$v;
    return False if $v ~~ Str && $v ~~ /^ \s* $/;
    return False if $v ~~ Positional && !$v.elems;
    return False if $v ~~ Associative && !$v.elems;
    True;
  }

  method attribute-names {
    @!fields.map(*.name).list;
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
    self.update-db-attrs;
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
    self.update-db-attrs;
  }

  method field-names {
    @!fields.map({ $_.name });
  }

  method update-db-attrs {
    for %!attrs.keys { %!attrs-db«$_» = %!attrs«$_» }
  }

  method save(Bool :$validate = True, Bool :$touch = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!destroyed;
    if !$validate || self.is-valid {
      self.update-foreign-keys;
      self.do-before-saves;
      self.touch-timestamps if $touch;

      my Bool $was-new = $!id == 0;
      my %snapshot;
      for self.changed -> $name {
        %snapshot{$name} = [%!attrs-db{$name}, %!attrs{$name}];
      }

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
      %!previous-changes = %snapshot;
      %!will-change = ();
      $!previously-new = $was-new;
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

  multi method update(%attrs) {
    for %attrs.keys -> $key {
      %!attrs{$key} = %attrs{$key};
    }
    self.save;
  }

  multi method update(@ids, %attrs) {
    my @objs;
    for @ids -> $id {
      my $obj = self.find($id);
      $obj.update(%attrs);
      @objs.push: $obj;
    }
    @objs;
  }

  multi method update(@ids, @attrs-list) {
    die 'Model.update: ids and attrs counts must match'
      unless @ids.elems == @attrs-list.elems;
    my @objs;
    for ^@ids.elems -> $i {
      my $obj = self.find(@ids[$i]);
      $obj.update(@attrs-list[$i]);
      @objs.push: $obj;
    }
    @objs;
  }

  method update-column(Str:D $name, $value --> Bool) {
    self.update-columns(%($name => $value));
  }

  method update-columns(%attrs --> Bool) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!destroyed;
    return False unless $!id;

    my %types;
    for @!fields -> $f { %types{$f.name} = $f.type if %attrs{$f.name}:exists }

    my $table = self.table-name;
    my $stmt = $!db.build-update(:$table, :id($!id), :%attrs, :%types);
    $!db.exec-stmt($stmt);

    for %attrs.kv -> $key, $val {
      %!attrs{$key} = $val;
      %!attrs-db{$key} = $val;
    }
    True;
  }

  method update-attribute(Str:D $name, $value --> Bool) {
    %!attrs{$name} = $value;
    self.save(:!validate);
  }

  method touch(*@names --> Bool) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!destroyed;
    return False unless $!id;

    my $now = DateTime.now;
    my %attrs;
    for @!fields -> $f {
      %attrs{$f.name} = $now if $f.name eq 'updated_at';
    }
    for @names -> $extra {
      %attrs{$extra} = $now if self.has-attribute($extra);
    }
    return False unless %attrs.elems;
    self.update-columns(%attrs);
  }

  method increment(Str:D $name, Numeric:D $n = 1) {
    %!attrs{$name} = (%!attrs{$name} // 0) + $n;
    self;
  }

  method increment-or-die(Str:D $name, Numeric:D $n = 1) {
    self.increment($name, $n);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
  }

  method decrement(Str:D $name, Numeric:D $n = 1) {
    self.increment($name, -$n);
  }

  method decrement-or-die(Str:D $name, Numeric:D $n = 1) {
    self.decrement($name, $n);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
  }

  method toggle(Str:D $name) {
    %!attrs{$name} = !%!attrs{$name};
    self;
  }

  method toggle-or-die(Str:D $name) {
    self.toggle($name);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
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
    $!destroyed = True;
    $!previously-persisted = True;
    $!previously-new = False;
    True;
  }

  method destroy-all {
    my $table = Utils.table-name(self);
    my %where;
    DB.shared.delete-records(:$table, :%where);
  }

  method update-all(*@args, *%kw --> Int) {
    self.all.update-all(|@args, |%kw);
  }

  method delete-all(--> Int) {
    self.all.delete-all;
  }

  method destroy-by(Hash:D $conditions --> Int) {
    self.where($conditions).destroy-all;
  }

  method delete-by(Hash:D $conditions --> Int) {
    self.where($conditions).delete-all;
  }

  multi method update-counters(Int:D $id, *%counters --> Int) {
    self.where({ :$id }).update-counters(|%counters);
  }

  multi method update-counters(@ids, *%counters --> Int) {
    self.where({ id => @ids.list }).update-counters(|%counters);
  }

  method !insert-types {
    my $table = Utils.table-name(self);
    my %types;
    for DB.shared.get-fields(:$table) -> $f { %types{$f[0]} = $f[1] }
    %types;
  }

  method insert(%attrs --> Int) {
    self!do-insert([%attrs.item], :skip-conflict)[0] // 0;
  }

  method insert-or-die(%attrs --> Int) {
    self!do-insert([%attrs.item])[0];
  }

  method insert-all(@rows) {
    self!do-insert(@rows.map(*.item).Array, :skip-conflict);
  }

  method insert-all-or-die(@rows) {
    self!do-insert(@rows.map(*.item).Array);
  }

  method !do-insert(@rows, Bool:D :$skip-conflict = False) {
    return () unless @rows.elems;
    my $table = Utils.table-name(self);
    my %types = self!insert-types;
    my @prepared = self.touch-rows-for-insert(@rows);
    DB.shared.insert-records(:$table, :rows(@prepared), :%types, :$skip-conflict);
  }

  method touch-rows-for-insert(@rows) {
    my $now = DateTime.now;
    my $table = Utils.table-name(self);
    my @fields = DB.shared.get-fields(:$table);
    my %names;
    for @fields -> $f { %names{$f[0]} = True }
    my @out;
    for @rows -> %row {
      my %copy = %row;
      %copy<created_at> //= $now if %names<created_at>;
      %copy<updated_at> //= $now if %names<updated_at>;
      @out.push: %copy;
    }
    @out;
  }

  method upsert(%attrs, :@unique-by = ('id',), :@update-cols = () --> Int) {
    self.upsert-all([%attrs.item], :@unique-by, :@update-cols);
  }

  method upsert-all(@rows, :@unique-by = ('id',), :@update-cols = () --> Int) {
    my @items = @rows.map(*.item).Array;
    return 0 unless @items.elems;
    my $table = Utils.table-name(self);
    my %types = self!insert-types;
    my @prepared = self.touch-rows-for-insert(@items);
    DB.shared.upsert-records(:$table, :rows(@prepared), :%types, :@unique-by, :@update-cols);
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

  method touch-all(*@names) {
    self.all.touch-all(|@names);
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

  method cache-key(--> Str) {
    return self.all.cache-key unless self.DEFINITE;
    my $table = self.table-name;
    return "$table/new" if $!id == 0;
    "$table/$!id";
  }

  method cache-version() {
    return self.all.cache-version unless self.DEFINITE;
    return Str unless %!attrs<updated_at>:exists && %!attrs<updated_at>.defined;
    %!attrs<updated_at>.Str;
  }

  method cache-key-with-version(--> Str) {
    return self.all.cache-key-with-version unless self.DEFINITE;
    my $v = self.cache-version;
    $v.defined ?? self.cache-key ~ '-' ~ $v !! self.cache-key;
  }

  method dup() {
    my $class = self.WHAT;
    my %attrs-copy;
    for %!attrs.kv -> $key, $val {
      next if $key eq any('id', 'created_at', 'updated_at');
      %attrs-copy{$key} = $val;
    }
    $class.new(:id(0), :record({ attrs => %attrs-copy }));
  }

  method clone() {
    my $class = self.WHAT;
    my %attrs-copy;
    for %!attrs.kv -> $key, $val { %attrs-copy{$key} = $val }
    my $new = $class.new(:id($!id), :record({ attrs => %attrs-copy }));
    $new.make-readonly if $!readonly;
    $new;
  }

  method becomes($klass) {
    die 'becomes: target must be a Model subclass'
      if $klass.DEFINITE || $klass !~~ Model;
    my %attrs-copy;
    for %!attrs.kv -> $key, $val { %attrs-copy{$key} = $val }
    my $new = $klass.new(:id($!id), :record({ attrs => %attrs-copy }));
    $new.make-readonly if $!readonly;
    $new;
  }

  method becomes-or-die($klass) {
    my $new = self.becomes($klass);
    if $new.has-attribute('type') {
      $new.write-attribute('type', $klass.^name);
    }
    $new;
  }

  method to-param() {
    return Str if $!id == 0;
    $!id.Str;
  }

  method to-key() {
    return Nil if $!id == 0;
    [$!id];
  }

  method filter-attribute(*@names) {
    @!filter-attributes.append(@names.map(*.Str));
    self;
  }

  method !is-filtered(Str:D $name --> Bool) {
    so @!filter-attributes.first({ ~$_ eq $name });
  }

  method serializable-hash(:$only = (), :$except = (), :$methods = () --> Hash) {
    my @only-s   = self!list-of-str($only);
    my @except-s = self!list-of-str($except);
    my @methods-s = self!list-of-str($methods);
    my %out;
    for self.attribute-names -> $name {
      next if @only-s.elems   && $name !(elem) @only-s;
      next if @except-s.elems && $name (elem) @except-s;
      %out{$name} = %!attrs{$name};
    }
    for @methods-s -> $name {
      %out{$name} = self."$name"();
    }
    %out;
  }

  method !list-of-str($v) {
    return () without $v;
    return $v.list.map(*.Str) if $v ~~ Iterable;
    ($v.Str,);
  }

  method as-json(*%opts --> Hash) {
    self!coerce-for-json(self.serializable-hash(|%opts));
  }

  method to-json(*%opts --> Str) {
    to-json(self.as-json(|%opts));
  }

  method !coerce-for-json($value) {
    given $value {
      when DateTime    { $value.Str }
      when Date        { $value.Str }
      when Hash        {
        my %h;
        for $value.kv -> $k, $v { %h{$k} = self!coerce-for-json($v) }
        %h;
      }
      when Positional  { $value.map({ self!coerce-for-json($_) }).list }
      default          { $value }
    }
  }

  method attribute-for-inspect(Str:D $name --> Str) {
    return '[FILTERED]' if self!is-filtered($name);
    my $value = %!attrs{$name};
    return 'Nil' without $value;
    given $value {
      when Str {
        my $s = $value.chars > 50 ?? $value.substr(0, 50) ~ '...' !! $value;
        '"' ~ $s ~ '"';
      }
      when DateTime | Date { '"' ~ $value.Str ~ '"' }
      when Bool            { $value ?? 'True' !! 'False' }
      default              { $value.Str }
    }
  }

  method inspect(--> Str) {
    my $class-name = self.WHAT.^name;
    my @parts;
    for self.attribute-names -> $name {
      @parts.push: $name ~ ': ' ~ self.attribute-for-inspect($name);
    }
    '#<' ~ $class-name ~ ' ' ~ @parts.join(', ') ~ '>';
  }

  method gist(--> Str) {
    return callsame() unless self.DEFINITE;
    self.inspect;
  }

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
