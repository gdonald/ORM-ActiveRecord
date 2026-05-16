
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
use ORM::ActiveRecord::Model::Attributes;
use ORM::ActiveRecord::Model::Bulk;
use ORM::ActiveRecord::Model::Callbacks;
use ORM::ActiveRecord::Model::Cloning;
use ORM::ActiveRecord::Model::DirtyTracking;
use ORM::ActiveRecord::Model::Finders;
use ORM::ActiveRecord::Model::RawSql;
use ORM::ActiveRecord::Model::Relations;
use ORM::ActiveRecord::Model::Serialization;
use ORM::ActiveRecord::Model::StatePredicates;
use ORM::ActiveRecord::Model::Suppressor;

class Model
  does ModelAttributes
  does ModelBulk
  does ModelCallbacks
  does ModelCloning
  does ModelDirtyTracking
  does ModelFinders
  does ModelRawSql
  does ModelRelations
  does ModelSerialization
  does ModelStatePredicates
  does ModelSuppressor
  is export
{
  has DB $!db;
  has Errors $.errors;
  has Validators $.validators;

  has %.record is rw;
  has %.has-manys;
  has %.has-ones;
  has %.habtms;
  has %.belongs-tos;

  has Int $.id is rw;
  has @.fields of Field;
  has %.attrs;
  has %.attrs-db;
  has Bool $.is-readonly is rw = False;
  has Bool $.is-destroyed is rw = False;
  has Bool $.was-new-record is rw = False;
  has Bool $.was-persisted is rw = False;
  has %.previous-changes is rw;
  has %.will-change is rw;

  has @.before-saves;
  has @.before-updates;
  has @.before-creates;

  has @.after-saves;
  has @.after-updates;
  has @.after-creates;

  has @.before-destroys;
  has @.after-destroys;

  has @.after-commits;
  has @.after-rollbacks;
  has @.after-create-commits;
  has @.after-update-commits;
  has @.after-destroy-commits;
  has @.after-save-commits;

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
      return 0 if self.is-polymorphic-assoc($base-name);
      return self."$base-name"().id;
    }

    if $name ~~ /^ 'add-' (.+) $/ {
      my $singular = ~$0;
      for %!habtms.keys -> $assoc {
        if Utils.singular($assoc) eq $singular {
          return self.habtm-add($assoc, @rest[0]);
        }
      }
    }
    if $name ~~ /^ 'remove-' (.+) $/ {
      my $singular = ~$0;
      for %!habtms.keys -> $assoc {
        if Utils.singular($assoc) eq $singular {
          return self.habtm-remove($assoc, @rest[0]);
        }
      }
    }
    if $name ~~ /^ 'clear-' (.+) $/ {
      my $assoc = ~$0;
      return self.habtm-clear($assoc) if %!habtms{$assoc}:exists;
    }

    return-rw %!attrs«$name» if %!attrs«$name»:exists;

    if any(%!has-manys.keys) eq $name {
      my $class = Mu:U;
      my $join-table = '';
      my $as-name = '';
      my $fkey-override = '';

      for %!has-manys{$name}.keys -> $key {
        given $key {
          when 'class' { $class = %!has-manys{$name}{'class'} }
          when 'class-name' { $class = self.resolve-class-name(~%!has-manys{$name}{'class-name'}) }
          when 'through' {
            $join-table = %!has-manys{$name}{'through'}.key;
            $class = self.get-through-class($name, $join-table);
          }
          when 'as' { $as-name = ~%!has-manys{$name}{'as'} }
          when 'foreign-key' { $fkey-override = ~%!has-manys{$name}{'foreign-key'} }
          default { say 'Unknown has-many type ' ~ %!has-manys{$name}; die }
        }
      }

      my Str $target-table = Utils.table-name($class);
      my @fields = self.get-fields($target-table);

      if $as-name {
        my $type-name = Utils.base-name(self.WHAT.^name);
        my %where = ($as-name ~ '_id') => $!id, ($as-name ~ '_type') => $type-name;
        return $!db.get-objects(:$class, :@fields, :table($target-table), :%where);
      }

      my $fkey-name = $fkey-override || Utils.base-name(self.fkey-name);
      return $!db.get-objects(:$class, :@fields, :table($target-table), :$join-table, :where($fkey-name => $!id));
    }

    if any(%!has-ones.keys) eq $name {
      my $fkey-name = Utils.base-name(self.fkey-name);
      my Str $table = $name ~ 's';
      my @fields = self.get-fields($table);
      my $class = Mu:U;
      my $join-table = '';

      for %!has-ones{$name}.keys -> $key {
        given $key {
          when 'class' { $class = %!has-ones{$name}{'class'} }
          when 'class-name' { $class = self.resolve-class-name(~%!has-ones{$name}{'class-name'}) }
          when 'through' {
            my $through-key = %!has-ones{$name}{'through'}.key;
            $join-table = $through-key ~ 's';
            $class = self.get-through-class-has-one($name, $through-key);
          }
          default { say 'Unknown has-one type ' ~ %!has-ones{$name}; die }
        }
      }

      if $join-table {
        my @objects = $!db.get-objects(:$class, :@fields, :$table, :$join-table, where => ($fkey-name => $!id).Hash, limit => 1);
        return @objects.elems ?? @objects.first !! Nil;
      }

      return $!db.get-object(:$class, :@fields, :$table, where => ($fkey-name => $!id).Hash);
    }

    if any(%!habtms.keys) eq $name {
      my $class = self.assoc-class-from-spec(%!habtms{$name});
      my $join-table = self.habtm-join-table($name);
      my $owner-key = Utils.base-name(self.fkey-name);
      my @fields = self.get-fields($name);
      return $!db.get-objects(:$class, :@fields, :table($name), :$join-table, :where(($owner-key => $!id).Hash));
    }

    if any(%!belongs-tos.keys) eq $name {
      if self.is-polymorphic-assoc($name) {
        my $type-attr = $name ~ '_type';
        my $type-name = %!attrs{$type-attr};
        return Nil unless $type-name;
        my $class = self.resolve-polymorphic-class($name, $type-name);
        return Nil if $class === Nil;
        my Str $table = Utils.table-name($class);
        my Int $id = %!attrs{$name ~ '_id'};
        return Nil unless $id;
        my @fields = self.get-fields($table);
        return $!db.get-object(:$class, :@fields, :$table, where => :$id);
      }
      my $class = self.assoc-class-from-spec(%!belongs-tos{$name});
      my Str $table = Utils.table-name($class);
      my Int $id = %!attrs{$name ~ '_id'};
      my @fields = self.get-fields($table);
      return $!db.get-object(:$class, :@fields, :$table, where => :$id);
    }

    return if $name ~~ /_confirmation/;

    say 'Unknown attribute or method "' ~ $name ~ '"'; die;
  }

  method get-through-class(Str:D $name, Str:D $join-table) {
    my $class = self.assoc-class-from-spec(%!has-manys{$join-table});
    my $singular = Utils.singular($name);
    my $instance = $class.new(:id(0));
    $instance.assoc-class-from-spec($instance.belongs-tos{$singular});
  }

  method get-through-class-has-one(Str:D $name, Str:D $through-key) {
    my $class = self.assoc-class-from-spec(%!has-ones{$through-key});
    my $instance = $class.new(:id(0));
    $instance.assoc-class-from-spec($instance.belongs-tos{$name});
  }

  method assoc-spec-has(\spec, Str:D $key --> Bool) {
    given spec {
      when Pair       { return spec.key eq $key }
      when Hash | Map { return so spec{$key}:exists }
    }
    False;
  }

  method assoc-spec-value(\spec, Str:D $key) {
    given spec {
      when Pair       { return spec.value if spec.key eq $key }
      when Hash | Map { return spec{$key}  if spec{$key}:exists }
    }
    Nil;
  }

  method assoc-class-from-spec(\spec) {
    return self.assoc-spec-value(spec, 'class') if self.assoc-spec-has(spec, 'class');
    if self.assoc-spec-has(spec, 'class-name') {
      return self.resolve-class-name(~self.assoc-spec-value(spec, 'class-name'));
    }
    Mu;
  }

  method resolve-class-name(Str:D $name) {
    my @parts = $name.split('::');
    my $obj = GLOBAL::{@parts.shift};
    die "Cannot resolve class-name '$name': not found in GLOBAL::"
      if $obj === Any || $obj ~~ Failure;
    for @parts -> $part {
      my $next = $obj.WHO{$part};
      die "Cannot resolve class-name '$name': not found in GLOBAL::"
        if $next === Any || $next ~~ Failure;
      $obj = $next;
    }
    $obj;
  }

  method table-name {
    self.WHAT.raku.lc ~ 's';
  }

  method fkey-name {
    self.WHAT.raku.lc ~ '_id';
  }

  method belongs-to(*%rest) {
    %!belongs-tos.push: %rest.keys.first => %rest.values.first;
  }

  method is-polymorphic-assoc(Str:D $name --> Bool) {
    return False unless %!belongs-tos{$name}:exists;
    my $spec = %!belongs-tos{$name};
    given $spec {
      when Pair { return $spec.key eq 'polymorphic' && $spec.value.so }
      when Hash | Map { return ($spec<polymorphic>:exists) && $spec<polymorphic>.so }
      default { return False }
    }
  }

  method polymorphic-classes(Str:D $name) {
    my $spec = %!belongs-tos{$name};
    given $spec {
      when Hash | Map {
        return @($spec<classes>) if $spec<classes>:exists;
      }
    }
    ();
  }

  method resolve-polymorphic-class(Str:D $name, Str:D $type-name) {
    my @candidates = self.polymorphic-classes($name);
    if @candidates.elems {
      for @candidates -> $c {
        return $c if Utils.base-name($c.^name) eq $type-name;
      }
      return Nil;
    }
    my $klass = GLOBAL::{$type-name};
    return Nil if $klass === Any;
    return Nil if $klass ~~ Failure;
    $klass;
  }

  method has-many(*%rest) {
    %!has-manys.push: %rest.keys.first => %rest.values.first;
  }

  method has-one(*%rest) {
    %!has-ones.push: %rest.keys.first => %rest.values.first;
  }

  method has-and-belongs-to-many(*%rest) {
    %!habtms.push: %rest.keys.first => %rest.values.first;
  }

  method habtm-join-table(Str:D $assoc --> Str) {
    for %!habtms{$assoc}.keys -> $key {
      return %!habtms{$assoc}{$key} if $key eq 'join-table';
    }
    ($assoc, self.table-name).sort.join('_');
  }

  method habtm-add(Str:D $assoc, Mu:D $record --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my $target-key = Utils.to-foreign-key($assoc);
    my $stmt = $!db.sanitize-sql-array([
      "INSERT INTO $join-table ($owner-key, $target-key) VALUES (?, ?)",
      $!id, $record.id,
    ]);
    $!db.exec-stmt($stmt);
    True;
  }

  method habtm-remove(Str:D $assoc, Mu:D $record --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my $target-key = Utils.to-foreign-key($assoc);
    my %where = ($owner-key => $!id, $target-key => $record.id);
    $!db.delete-records(:table($join-table), :%where);
    True;
  }

  method habtm-clear(Str:D $assoc --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my %where = ($owner-key => $!id).Hash;
    $!db.delete-records(:table($join-table), :%where);
    True;
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

  method locking-column(--> Str) { 'lock_version' }

  method is-locking-enabled(--> Bool) {
    so self.fields.first({ .name eq self.locking-column });
  }

  method save(Bool :$validate = True, Bool :$touch = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
    return True if self.is-suppressed;
    if !$validate || self.is-valid {
      self.update-foreign-keys;
      self.do-before-saves;
      self.touch-timestamps if $touch;

      my Bool $was-new = $!id == 0;
      my Bool $locking = self.is-locking-enabled;
      my $lock-col = self.locking-column;
      my $prev-lock;
      if $locking && !$was-new {
        $prev-lock = (%!attrs-db{$lock-col} // 0).Int;
        %!attrs{$lock-col} = $prev-lock + 1;
      }

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
          if $locking {
            my %types = @!fields.map({ .name => .type }).Hash;
            my $affected = $!db.update-records(
              :table(self.table-name),
              :attrs(%!attrs),
              :%types,
              :where({ id => $!id, $lock-col => $prev-lock }),
            );
            if $affected == 0 {
              die X::StaleObjectError.new(model => self.WHAT.^name);
            }
          } else {
            $!db.update-object(self);
          }
          self.do-after-updates;
        }
      }

      self.do-after-saves;
      self.update-db-attrs;
      %!previous-changes = %snapshot;
      %!will-change = ();
      $!was-new-record = $was-new;
      $!db.register-txn-callback(self, $was-new ?? 'create' !! 'update');
      return True;
    }
    False;
  }

  method update-foreign-keys {
    for $.belongs-tos.keys -> $key {
      next unless $.attrs{$key};
      if self.is-polymorphic-assoc($key) {
        my $record = $.attrs{$key};
        next unless $record ~~ Model;
        $.attrs{$key ~ '_id'}   = $record.id;
        $.attrs{$key ~ '_type'} = Utils.base-name($record.WHAT.^name);
        $.attrs{$key}:delete;
      }
      else {
        my $assoc-class = self.assoc-class-from-spec($.belongs-tos{$key});
        if $assoc-class !=== Mu && $.attrs{$key} ~~ $assoc-class {
          $.attrs{$key ~ '_id'} = $.attrs{$key}.id;
          $.attrs{$key}:delete;
        }
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
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
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
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
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
    $!db.register-txn-callback(self, 'destroy');
    True;
  }

  method delete {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    return False unless $!id;
    my $table = Utils.table-name(self);
    my %where = id => $!id;
    $!db.delete-records(:$table, :%where);
    $!id = 0;
    %!attrs<id> = 0;
    $!is-destroyed = True;
    $!was-persisted = True;
    $!was-new-record = False;
    True;
  }

  method lock-or-die($mode = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
    die "lock-or-die: record has no id (call save first)" unless $!id;
    my $klass = self.WHAT;
    my @rows = $klass.where({ id => $!id }).lock($mode).all;
    die X::RecordNotFound.new(:model($klass.^name)) unless @rows.elems;
    my $fresh = @rows[0];
    for $fresh.attrs.kv -> $k, $v { %!attrs{$k} = $v }
    self.update-db-attrs;
    %!will-change = ();
    self;
  }

  method with-lock(&block, $mode = True) {
    $!db.transaction({
      self.lock-or-die($mode);
      block(self);
    });
  }

  method becomes($klass) {
    die 'becomes: target must be a Model subclass'
      if $klass.DEFINITE || $klass !~~ Model;
    my %attrs-copy;
    for %!attrs.kv -> $key, $val { %attrs-copy{$key} = $val }
    my $new = $klass.new(:id($!id), :record({ attrs => %attrs-copy }));
    $new.make-readonly if $!is-readonly;
    $new;
  }

  method becomes-or-die($klass) {
    my $new = self.becomes($klass);
    if $new.has-attribute('type') {
      $new.write-attribute('type', $klass.^name);
    }
    $new;
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
