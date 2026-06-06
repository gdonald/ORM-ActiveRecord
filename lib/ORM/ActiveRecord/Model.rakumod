
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Connection::Switching;
use ORM::ActiveRecord::Support::Environment;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Errors::Errors;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Message;
use ORM::ActiveRecord::Relation::Collection;
use ORM::ActiveRecord::Relation::Query;
use ORM::ActiveRecord::Relation::Scope;
use ORM::ActiveRecord::Relation::Scopes;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Validations::Validator;
use ORM::ActiveRecord::Validations::Validators;
use ORM::ActiveRecord::Model::Attributes;
use ORM::ActiveRecord::Model::Bulk;
use ORM::ActiveRecord::Model::Encryption;
use ORM::ActiveRecord::Model::Enum;
use ORM::ActiveRecord::Model::Typing;
use ORM::ActiveRecord::Model::Callbacks;
use ORM::ActiveRecord::Model::Cloning;
use ORM::ActiveRecord::Model::DirtyTracking;
use ORM::ActiveRecord::Model::Finders;
use ORM::ActiveRecord::Model::Inheritance;
use ORM::ActiveRecord::Model::RawSql;
use ORM::ActiveRecord::Model::Secure;
use ORM::ActiveRecord::Model::Relations;
use ORM::ActiveRecord::Model::Serialization;
use ORM::ActiveRecord::Model::StatePredicates;
use ORM::ActiveRecord::Model::StrictLoading;
use ORM::ActiveRecord::Model::Suppressor;

class Model
  does ModelAttributes
  does ModelBulk
  does ModelCallbacks
  does ModelEncryption
  does ModelEnum
  does ModelCloning
  does ModelDirtyTracking
  does ModelFinders
  does ModelInheritance
  does ModelRawSql
  does ModelSecure
  does ModelRelations
  does ModelSerialization
  does ModelStatePredicates
  does ModelStrictLoading
  does ModelSuppressor
  does ModelTyping
  is export
{
  my %connection-of;

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
  has Bool $.is-strict-loading is rw = False;
  has Bool $.is-destroyed is rw = False;
  has Bool $.was-new-record is rw = False;
  has Bool $.was-persisted is rw = False;
  has Str  $.validation-context is rw;
  has %.previous-changes is rw;
  has %.will-change is rw;

  has @.before-saves;
  has @.before-updates;
  has @.before-creates;

  has @.after-saves;
  has @.after-updates;
  has @.after-creates;

  has @.around-saves;
  has @.around-updates;
  has @.around-creates;
  has @.around-destroys;

  has @.before-destroys;
  has @.after-destroys;

  has @.before-validations;
  has @.after-validations;

  has @.after-initializes;
  has @.after-finds;
  has @.after-touches;

  has @.after-commits;
  has @.after-rollbacks;
  has @.after-create-commits;
  has @.after-update-commits;
  has @.after-destroy-commits;
  has @.after-save-commits;

  has %.callback-terminators;
  has Bool $.was-found-from-db is rw = False;

  has @.filter-attributes;

  has %.assoc-cache;

  my Scopes $.scopes;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD(Int:D :$!id, :%!record) {
    $!db = self.db;
    $!errors = Errors.new;
    $!validators = Validators.new;

    self.WHAT.register-sti;
    @!fields = self.get-fields(self.table-name);
    self.init-attrs;

    if %!record && %!record<attrs> {
      self.merge-attrs(%!record<attrs>);
      self.update-db-attrs if $!id;
      $!was-found-from-db = $!id != 0;
    } elsif $!id {
      self.get-attrs(:$!id);
      $!was-found-from-db = True;
    }
  }

  method new(|c) {
    my $obj = self.bless(|c);
    $obj.apply-attribute-types;
    $obj.do-after-initializes;
    $obj.do-after-finds if $obj.was-found-from-db;
    $obj;
  }

  # Bind this model to one or more named connections (from
  # config/application.json). Three forms:
  #
  #   connects-to('analytics')                                  # single connection
  #   connects-to(database => { writing => 'primary', reading => 'replica' })
  #   connects-to(shards => { default   => { writing => 'p',  reading => 'r'  },
  #                           shard_one => { writing => 's1', reading => 's1r' } })
  #
  # Stored normalized as { shards => { <shard> => { <role> => <connection> } } }.
  # `connected-to(role:/shard:)` then selects which connection a query uses;
  # unbound models always use the primary connection.
  proto method connects-to(|) {*}

  multi method connects-to(Str:D $name) {
    %connection-of{self.^name} = %( shards => %( default => %( writing => $name, reading => $name ) ) );
  }

  multi method connects-to(*%opts) {
    my %shards;
    if %opts<shards>:exists {
      for %opts<shards>.kv -> $shard, $roles { %shards{$shard} = $roles.hash }
    }
    %shards<default> = %opts<database>.hash if %opts<database>:exists;
    %connection-of{self.^name} = %( shards => %shards );
  }

  method connection-name(--> Str) {
    return active-connection() if active-connection().defined;

    my $spec = %connection-of{self.^name};
    return default-connection() without $spec;

    my $shard = active-shard() // 'default';
    my $role  = active-role()  // 'writing';

    my %shards = $spec<shards>;
    my %roles  = (%shards{$shard} // %shards<default> // %()).hash;

    %roles{$role} // %roles<writing> // %roles.values.first // default-connection();
  }

  # Run a block with the connection role / shard (or an explicit connection
  # name) switched, restoring the previous context afterward. Affects every
  # model's query routing for the dynamic extent of the block.
  method connected-to(&block, :$role, :$shard, :$connection) {
    # Resolve the inherited context here, where there is no `my $*AR-*`
    # declaration to shadow the outer dynamic variables (a `my $*X` is
    # hoisted over the whole method, so reading it even before assignment
    # would see the new, uninitialized binding). The actual rebinding happens
    # in a separate method.
    self!run-connected(
      role       => ($role       // active-role()),
      shard      => ($shard      // active-shard()),
      connection => ($connection // active-connection()),
      &block,
    );
  }

  method !run-connected(&block, :$role, :$shard, :$connection) {
    my $*AR-ROLE       = $role;
    my $*AR-SHARD      = $shard;
    my $*AR-CONNECTION = $connection;
    block();
  }

  method connected-to-many(@classes, &block, :$role, :$shard) {
    self.connected-to(&block, :$role, :$shard);
  }

  method db(--> DB) {
    DB.shared(name => self.connection-name);
  }

  method FALLBACK(Str:D $name, *@rest) is raw {
    if $?CLASS.scopes.exists($name) {
      return $?CLASS.scopes.exec($name);
    }

    # Enum value predicate: record.is-active
    if self.DEFINITE && $name ~~ /^ 'is-' (.+) $/ {
      my $value = ~$0;
      with self.enum-attr-for-value($value) -> $attr {
        return (self.read-attribute($attr) // '') eq $value;
      }
    }
    # Enum bang setter: record.active-bang assigns the value and saves
    if self.DEFINITE && $name ~~ /^ (.+) '-bang' $/ {
      my $value = ~$0;
      with self.enum-attr-for-value($value) -> $attr {
        self.write-attribute($attr, $value);
        self.save;
        return self;
      }
    }
    # Enum class scope: Order.active
    unless self.DEFINITE {
      with self.enum-attr-for-value($name) -> $attr {
        return self.where({ $attr => self.enum-backing($attr, $name) });
      }
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

    if $name ~~ /^ 'build-' (.+) $/ {
      my $assoc = ~$0;
      if %!has-ones{$assoc}:exists {
        my %attrs = @rest.elems ?? @rest[0] !! {};
        return self.has-one-build($assoc, %attrs);
      }
    }
    if $name ~~ /^ 'create-' (.+) '-bang' $/ {
      my $assoc = ~$0;
      if %!has-ones{$assoc}:exists {
        my %attrs = @rest.elems ?? @rest[0] !! {};
        return self.has-one-create-bang($assoc, %attrs);
      }
    }
    if $name ~~ /^ 'create-' (.+) $/ {
      my $assoc = ~$0;
      if %!has-ones{$assoc}:exists {
        my %attrs = @rest.elems ?? @rest[0] !! {};
        return self.has-one-create($assoc, %attrs);
      }
    }

    if self.DEFINITE {
      with self.store-accessor-column($name) -> $column {
        %!attrs{$column} = %() unless %!attrs{$column} ~~ Associative;
        return-rw %!attrs{$column}{$name};
      }
    }

    return-rw %!attrs«$name» if %!attrs«$name»:exists;

    if any(%!has-manys.keys) eq $name {
      my $spec = %!has-manys{$name};
      if %!assoc-cache{$name}:exists {
        my $cached-class = self.assoc-class-from-spec($spec) // Mu:U;
        return self.wrap-collection(%!assoc-cache{$name}.list, $name, $spec, $cached-class, @rest);
      }
      self.check-strict-loading($name, $spec);
      my $class = Mu:U;
      my $join-table = '';
      my $as-name = '';
      my $fkey-override = '';
      my $pkey-col = 'id';

      for $spec.keys -> $key {
        given $key {
          when 'class' { $class = $spec{'class'} }
          when 'class-name' { $class = self.resolve-class-name(~$spec{'class-name'}) }
          when 'through' {
            $join-table = $spec{'through'}.key;
            $class = self.get-through-class($name, $join-table, $spec);
          }
          when 'as' { $as-name = ~$spec{'as'} }
          when 'foreign-key' { $fkey-override = ~$spec{'foreign-key'} }
          when 'primary-key' { $pkey-col = ~$spec{'primary-key'} }
          when 'inverse-of' { }
          when 'dependent' { }
          when 'extension' { }
          when 'source' | 'source-type' | 'disable-joins' | 'strict-loading' | 'autosave' | 'validate' | 'query-constraints' | 'scope' { }
          default { say 'Unknown has-many type ' ~ $spec; die }
        }
      }

      my Str $target-table = Utils.table-name($class);
      my @fields = self.get-fields($target-table);
      my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
      my $scope-block = self.assoc-scope-block($spec);

      if $as-name {
        my $type-name = self.polymorphic-name;
        my %where = ($as-name ~ '_id') => $pkey-val, ($as-name ~ '_type') => $type-name;
        my @records;
        if $scope-block.defined {
          my $q = Query.new(:$class, :params(%where));
          $q = self.apply-assoc-scope($scope-block, $q, @rest);
          @records = $q.all;
        } else {
          @records = $!db.get-objects(:$class, :@fields, :table($target-table), :%where);
        }
        self.attach-inverse(@records, $spec, $class);
        return self.wrap-collection(@records, $name, $spec, $class, @rest);
      }

      my $fkey-name = $fkey-override || Utils.base-name(self.fkey-name);

      if !$join-table && self.assoc-spec-has($spec, 'query-constraints') {
        my @cols = self.assoc-spec-value($spec, 'query-constraints').list;
        my $natural-fkey = $fkey-override || Utils.base-name(self.fkey-name);
        my %where;
        for @cols -> $col {
          %where{$col} = $col eq $natural-fkey ?? $pkey-val !! %!attrs{$col};
        }
        my @records;
        if $scope-block.defined {
          my $q = Query.new(:$class, :params(%where));
          $q = self.apply-assoc-scope($scope-block, $q, @rest);
          @records = $q.all;
        } else {
          @records = $!db.get-objects(:$class, :@fields, :table($target-table), :%where);
        }
        self.attach-inverse(@records, $spec, $class);
        return self.wrap-collection(@records, $name, $spec, $class, @rest);
      }

      if $join-table && self.assoc-spec-has($spec, 'disable-joins') && so self.assoc-spec-value($spec, 'disable-joins') {
        my $target-fkey = Utils.to-foreign-key($target-table);
        my $select = $!db.sanitize-sql-array([
          "SELECT $target-fkey FROM $join-table WHERE $fkey-name = ?",
          $pkey-val,
        ]);
        my @rows = $!db.exec-stmt($select);
        my @ids = @rows.map({ $_[0] }).grep(*.defined);
        my @records;
        if @ids.elems {
          if $scope-block.defined {
            my $q = Query.new(:$class, :params({ id => @ids.list }));
            $q = self.apply-assoc-scope($scope-block, $q, @rest);
            @records = $q.all;
          } else {
            @records = $!db.get-objects(:$class, :@fields, :table($target-table), :where({ id => @ids }));
          }
        }
        self.attach-inverse(@records, $spec, $class);
        return self.wrap-collection(@records, $name, $spec, $class, @rest);
      }

      if $join-table && $scope-block.defined {
        my $target-fkey = Utils.to-foreign-key($target-table);
        my $select = $!db.sanitize-sql-array([
          "SELECT $target-fkey FROM $join-table WHERE $fkey-name = ?",
          $pkey-val,
        ]);
        my @rows = $!db.exec-stmt($select);
        my @ids = @rows.map({ $_[0] }).grep(*.defined);
        my @records;
        if @ids.elems {
          my $q = Query.new(:$class, :params({ id => @ids.list }));
          $q = self.apply-assoc-scope($scope-block, $q, @rest);
          @records = $q.all;
        }
        self.attach-inverse(@records, $spec, $class);
        return self.wrap-collection(@records, $name, $spec, $class, @rest);
      }

      my @records;
      if $scope-block.defined {
        my $q = Query.new(:$class, :params({ $fkey-name => $pkey-val }));
        $q = self.apply-assoc-scope($scope-block, $q, @rest);
        @records = $q.all;
      } else {
        @records = $!db.get-objects(:$class, :@fields, :table($target-table), :$join-table, :where($fkey-name => $pkey-val));
      }
      self.attach-inverse(@records, $spec, $class);
      return self.wrap-collection(@records, $name, $spec, $class, @rest);
    }

    if any(%!has-ones.keys) eq $name {
      my $spec = %!has-ones{$name};
      return %!assoc-cache{$name} if %!assoc-cache{$name}:exists;
      self.check-strict-loading($name, $spec);
      my $fkey-name = Utils.base-name(self.fkey-name);
      my $class = Mu:U;
      my $join-table = '';
      my $pkey-col = 'id';

      for $spec.keys -> $key {
        given $key {
          when 'class' { $class = $spec{'class'} }
          when 'class-name' { $class = self.resolve-class-name(~$spec{'class-name'}) }
          when 'through' {
            my $through-key = $spec{'through'}.key;
            $join-table = $through-key ~ 's';
            $class = self.get-through-class-has-one($name, $through-key, $spec);
          }
          when 'foreign-key' { $fkey-name = ~$spec{'foreign-key'} }
          when 'primary-key' { $pkey-col = ~$spec{'primary-key'} }
          when 'inverse-of' { }
          when 'dependent' { }
          when 'source' | 'source-type' | 'disable-joins' | 'strict-loading' | 'autosave' | 'validate' | 'query-constraints' | 'scope' { }
          default { say 'Unknown has-one type ' ~ $spec; die }
        }
      }

      my Str $table = $class === Mu:U ?? $name ~ 's' !! Utils.table-name($class);
      my @fields = self.get-fields($table);
      my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
      my $scope-block = self.assoc-scope-block($spec);

      if $join-table && self.assoc-spec-has($spec, 'disable-joins') && so self.assoc-spec-value($spec, 'disable-joins') {
        my $target-fkey = Utils.to-foreign-key($table);
        my $select = $!db.sanitize-sql-array([
          "SELECT $target-fkey FROM $join-table WHERE $fkey-name = ? LIMIT 1",
          $pkey-val,
        ]);
        my @rows = $!db.exec-stmt($select);
        return Nil unless @rows.elems;
        my $target-id = @rows[0][0];
        return Nil unless $target-id.defined;
        my $obj;
        if $scope-block.defined {
          my $q = Query.new(:$class, :params({ id => $target-id }));
          $q = self.apply-assoc-scope($scope-block, $q, @rest);
          $obj = $q.first;
        } else {
          $obj = $!db.get-object(:$class, :@fields, :$table, where => { id => $target-id });
        }
        return Nil unless $obj.defined;
        self.attach-inverse-single($obj, $spec, $class);
        return $obj;
      }

      if $join-table {
        if $scope-block.defined {
          my $target-fkey = Utils.to-foreign-key($table);
          my $select = $!db.sanitize-sql-array([
            "SELECT $target-fkey FROM $join-table WHERE $fkey-name = ?",
            $pkey-val,
          ]);
          my @rows = $!db.exec-stmt($select);
          return Nil unless @rows.elems;
          my @ids = @rows.map({ $_[0] }).grep(*.defined);
          return Nil unless @ids.elems;
          my $q = Query.new(:$class, :params({ id => @ids.list }));
          $q = self.apply-assoc-scope($scope-block, $q, @rest);
          my $only = $q.first;
          return Nil unless $only.defined;
          self.attach-inverse-single($only, $spec, $class);
          return $only;
        }
        my @objects = $!db.get-objects(:$class, :@fields, :$table, :$join-table, where => ($fkey-name => $pkey-val).Hash, limit => 1);
        return Nil unless @objects.elems;
        my $only = @objects.first;
        self.attach-inverse-single($only, $spec, $class);
        return $only;
      }

      my $obj;
      if $scope-block.defined {
        my $q = Query.new(:$class, :params({ $fkey-name => $pkey-val }));
        $q = self.apply-assoc-scope($scope-block, $q, @rest);
        $obj = $q.first;
      } else {
        $obj = $!db.get-object(:$class, :@fields, :$table, where => ($fkey-name => $pkey-val).Hash);
      }
      return Nil unless $obj.defined;
      self.attach-inverse-single($obj, $spec, $class);
      return $obj;
    }

    if any(%!habtms.keys) eq $name {
      my $spec = %!habtms{$name};
      return %!assoc-cache{$name}.list if %!assoc-cache{$name}:exists;
      self.check-strict-loading($name, $spec);
      my $class = self.assoc-class-from-spec($spec);
      my $target-table = $class !=== Mu ?? Utils.table-name($class) !! $name;
      my $join-table = self.habtm-join-table($name);
      my $owner-key = Utils.base-name(self.fkey-name);
      my @fields = self.get-fields($target-table);
      my $scope-block = self.assoc-scope-block($spec);
      if $scope-block.defined {
        my $target-fkey = self.assoc-fkey-from-spec($spec, Utils.to-foreign-key($target-table));
        my $select = $!db.sanitize-sql-array([
          "SELECT $target-fkey FROM $join-table WHERE $owner-key = ?",
          $!id,
        ]);
        my @rows = $!db.exec-stmt($select);
        my @ids = @rows.map({ $_[0] }).grep(*.defined);
        return () unless @ids.elems;
        my $q = Query.new(:$class, :params({ id => @ids.list }));
        $q = self.apply-assoc-scope($scope-block, $q, @rest);
        return $q.all;
      }
      return $!db.get-objects(:$class, :@fields, :table($target-table), :$join-table, :where(($owner-key => $!id).Hash));
    }

    if any(%!belongs-tos.keys) eq $name {
      my $spec = %!belongs-tos{$name};
      return %!assoc-cache{$name} if %!assoc-cache{$name}:exists;
      self.check-strict-loading($name, $spec);
      if self.is-polymorphic-assoc($name) {
        my $type-attr = $name ~ '_type';
        my $type-name = %!attrs{$type-attr};
        return Nil unless $type-name;
        my $class = self.resolve-polymorphic-class($name, $type-name);
        return Nil unless $class.defined === False && $class !=== Any && $class !=== Mu;
        my Str $table = Utils.table-name($class);
        my Int $id = %!attrs{$name ~ '_id'};
        return Nil unless $id;
        my @fields = self.get-fields($table);
        return $!db.get-object(:$class, :@fields, :$table, where => :$id);
      }
      my $class = self.assoc-class-from-spec($spec);
      my Str $table = Utils.table-name($class);
      my Str $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
      my Str $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
      my $fkey-val = %!attrs{$fkey-col};
      return Nil unless $fkey-val;
      my @fields = self.get-fields($table);
      my $scope-block = self.assoc-scope-block($spec);
      if $scope-block.defined {
        my $q = Query.new(:$class, :params({ $pkey-col => $fkey-val }));
        $q = self.apply-assoc-scope($scope-block, $q, @rest);
        return $q.first;
      }
      my %where = ($pkey-col => $fkey-val);
      return $!db.get-object(:$class, :@fields, :$table, :%where);
    }

    return if $name ~~ /_confirmation/;

    say 'Unknown attribute or method "' ~ $name ~ '"'; die;
  }

  method assoc-source-name(\spec, Str:D $default --> Str) {
    return $default unless self.assoc-spec-has(spec, 'source');
    my $v = self.assoc-spec-value(spec, 'source');
    given $v {
      when Pair { return ~$v.key }
      default   { return ~$v }
    }
  }

  method assoc-source-type(\spec --> Str) {
    return '' unless self.assoc-spec-has(spec, 'source-type');
    ~self.assoc-spec-value(spec, 'source-type');
  }

  method get-through-class(Str:D $name, Str:D $join-table, \spec) {
    my $class = self.assoc-class-from-spec(%!has-manys{$join-table});
    my $singular = self.assoc-source-name(spec, Utils.singular($name));
    my $instance = $class.new(:id(0));
    if $instance.is-polymorphic-assoc($singular) {
      my $stype = self.assoc-source-type(spec);
      die "has_many :through with polymorphic source '$singular' requires source-type:"
        unless $stype;
      return $instance.resolve-polymorphic-class($singular, $stype);
    }
    $instance.assoc-class-from-spec($instance.belongs-tos{$singular});
  }

  method get-through-class-has-one(Str:D $name, Str:D $through-key, \spec) {
    my $class = self.assoc-class-from-spec(%!has-ones{$through-key});
    my $source = self.assoc-source-name(spec, $name);
    my $instance = $class.new(:id(0));
    if $instance.is-polymorphic-assoc($source) {
      my $stype = self.assoc-source-type(spec);
      die "has_one :through with polymorphic source '$source' requires source-type:"
        unless $stype;
      return $instance.resolve-polymorphic-class($source, $stype);
    }
    $instance.assoc-class-from-spec($instance.belongs-tos{$source});
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

  method assoc-fkey-from-spec(\spec, Str:D $default --> Str) {
    return ~self.assoc-spec-value(spec, 'foreign-key') if self.assoc-spec-has(spec, 'foreign-key');
    $default;
  }

  method assoc-pkey-from-spec(\spec, Str:D $default = 'id' --> Str) {
    return ~self.assoc-spec-value(spec, 'primary-key') if self.assoc-spec-has(spec, 'primary-key');
    $default;
  }

  method assoc-dependent(\spec --> Str) {
    return '' unless self.assoc-spec-has(spec, 'dependent');
    my $v = self.assoc-spec-value(spec, 'dependent');
    my $raw = '';
    given $v {
      when Pair { $raw = ~$v.key }
      default   { $raw = ~$v }
    }
    $raw.subst('_', '-', :g);
  }

  method is-belongs-to-optional(Str:D $name --> Bool) {
    return False unless %!belongs-tos{$name}:exists;
    my $spec = %!belongs-tos{$name};
    if self.assoc-spec-has($spec, 'optional') {
      return so self.assoc-spec-value($spec, 'optional');
    }
    if self.assoc-spec-has($spec, 'required') {
      return not so self.assoc-spec-value($spec, 'required');
    }
    False;
  }

  method assoc-counter-cache-column(\spec --> Str) {
    return '' unless self.assoc-spec-has(spec, 'counter-cache');
    my $v = self.assoc-spec-value(spec, 'counter-cache');
    given $v {
      when Bool { return $v ?? self.table-name ~ '_count' !! '' }
      default   { return ~$v }
    }
  }

  method assoc-touch-columns(\spec --> List) {
    return () unless self.assoc-spec-has(spec, 'touch');
    my $v = self.assoc-spec-value(spec, 'touch');
    given $v {
      when Bool { return $v ?? ('updated_at',) !! () }
      default   { return ('updated_at', ~$v) }
    }
  }

  method assoc-strict-loading(\spec --> Bool) {
    return False unless self.assoc-spec-has(spec, 'strict-loading');
    so self.assoc-spec-value(spec, 'strict-loading');
  }

  method check-strict-loading(Str:D $name, \spec) {
    return unless self.is-association-strict-loading(spec);
    die X::StrictLoadingViolationError.new(
      :model(self.WHAT.^name),
      :association($name),
    );
  }

  method is-association-strict-loading(\spec --> Bool) {
    return True if $!is-strict-loading;
    return True if self.is-strict-loading-by-default;
    self.assoc-strict-loading(spec);
  }

  method assoc-autosave(\spec) {
    return Bool unless self.assoc-spec-has(spec, 'autosave');
    so self.assoc-spec-value(spec, 'autosave');
  }

  method assoc-validate-flag(\spec --> Bool) {
    return False unless self.assoc-spec-has(spec, 'validate');
    so self.assoc-spec-value(spec, 'validate');
  }

  method assoc-scope-block(\spec) {
    return Block unless self.assoc-spec-has(spec, 'scope');
    my $v = self.assoc-spec-value(spec, 'scope');
    $v ~~ Block ?? $v !! Block;
  }

  method apply-assoc-scope(Block $block, Query:D $q, @args) {
    return $q unless $block.defined;
    my $result = $block.count == 1 ?? $block($q) !! $block($q, |@args);
    $result ~~ Query ?? $result !! $q;
  }

  method assoc-inverse-name(\spec --> Str) {
    return '' unless self.assoc-spec-has(spec, 'inverse-of');
    my $v = self.assoc-spec-value(spec, 'inverse-of');
    given $v {
      when Pair { return ~$v.key }
      default   { return ~$v }
    }
  }

  method assoc-auto-inverse-disabled(\spec --> Bool) {
    for <foreign-key primary-key through as polymorphic> -> $opt {
      return True if self.assoc-spec-has(spec, $opt);
    }
    False;
  }

  method auto-detect-inverse(Mu $target-class --> Str) {
    return '' if $target-class === Mu;
    my $owner = self.WHAT;
    my $instance;
    try { $instance = $target-class.new(:id(0)) };
    return '' unless $instance.defined;
    my @hits;
    for $instance.belongs-tos.kv -> $bname, $bspec {
      next if $instance.assoc-auto-inverse-disabled($bspec);
      my $klass = Mu;
      try { $klass = $instance.assoc-class-from-spec($bspec) };
      next if $klass === Mu || $klass === Any;
      @hits.push($bname) if $klass === $owner;
    }
    return @hits[0] if @hits.elems == 1;
    '';
  }

  method resolve-inverse-name(\spec, Mu $target-class --> Str) {
    my $explicit = self.assoc-inverse-name(spec);
    return $explicit if $explicit;
    return '' if self.assoc-auto-inverse-disabled(spec);
    self.auto-detect-inverse($target-class);
  }

  method attach-inverse(@records, \spec, Mu $target-class) {
    return unless @records.elems;
    my $inverse = self.resolve-inverse-name(spec, $target-class);
    return unless $inverse;
    for @records -> $r {
      $r.attrs{$inverse} = self;
    }
  }

  method attach-inverse-single(Mu $record, \spec, Mu $target-class) {
    return unless $record.defined;
    my $inverse = self.resolve-inverse-name(spec, $target-class);
    return unless $inverse;
    $record.attrs{$inverse} = self;
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
    Utils.base-name(self.^name).lc ~ 's';
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

  method polymorphic-name {
    Utils.base-name(self.WHAT.^name);
  }

  method polymorphic-class-for(Str:D $assoc-name, Str:D $type-name) {
    my @candidates = self.polymorphic-classes($assoc-name);
    if @candidates.elems {
      for @candidates -> $c {
        return $c if $c.polymorphic-name eq $type-name;
      }
      return Nil;
    }
    Utils.lookup-class($type-name);
  }

  method resolve-polymorphic-class(Str:D $name, Str:D $type-name) {
    self.polymorphic-class-for($name, $type-name);
  }

  method has-many(*%rest) {
    %!has-manys.push: %rest.keys.first => %rest.values.first;
  }

  method assoc-extension-role(\spec) {
    return Mu unless self.assoc-spec-has(spec, 'extension');
    self.assoc-spec-value(spec, 'extension');
  }

  method wrap-collection(@records, Str:D $name, $spec, Mu $class, @args) {
    my @col = @records;
    @col does CollectionProxy;
    @col.owner        = self;
    @col.spec         = $spec;
    @col.target-class = $class;
    @col.assoc-name   = $name;
    @col.args         = @args.Array;
    my $ext = self.assoc-extension-role($spec);
    @col does $ext if $ext !=== Mu;
    @col;
  }

  method has-one(*%rest) {
    %!has-ones.push: %rest.keys.first => %rest.values.first;
  }

  method has-one-attrs(Str:D $name, %attrs) {
    my $spec = %!has-ones{$name};
    die "build-/create-$name is not supported for has_one :through"
      if self.assoc-spec-has($spec, 'through');
    my $class = self.assoc-class-from-spec($spec);
    die "build-/create-$name needs class: or class-name: on the has-one"
      if $class === Mu;
    my $fkey-col = self.assoc-fkey-from-spec($spec, Utils.base-name(self.fkey-name));
    my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
    my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
    my %a = %attrs;
    %a{$fkey-col} = $pkey-val;
    ($class, %a);
  }

  method has-one-build(Str:D $name, %attrs) {
    my ($class, %a) = self.has-one-attrs($name, %attrs);
    $class.build(%a);
  }

  method has-one-create(Str:D $name, %attrs) {
    my ($class, %a) = self.has-one-attrs($name, %attrs);
    $class.create(%a);
  }

  method has-one-create-bang(Str:D $name, %attrs) {
    my ($class, %a) = self.has-one-attrs($name, %attrs);
    $class.create-bang(%a);
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

  method habtm-target-key(Str:D $assoc --> Str) {
    my $spec = %!habtms{$assoc};
    my $class = self.assoc-class-from-spec($spec);
    my $target-table = $class !=== Mu ?? Utils.table-name($class) !! $assoc;
    self.assoc-fkey-from-spec($spec, Utils.to-foreign-key($target-table));
  }

  method habtm-add(Str:D $assoc, Mu:D $record --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my $target-key = self.habtm-target-key($assoc);
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
    my $target-key = self.habtm-target-key($assoc);
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

  method counter-cache-bump(Int:D $fkey-val, Str:D $target-table, Str:D $col, Str:D $pkey-col, Int:D $delta) {
    return unless $fkey-val;
    my $stmt = $!db.sanitize-sql-array([
      "UPDATE $target-table SET $col = $col + ? WHERE $pkey-col = ?",
      $delta, $fkey-val,
    ]);
    $!db.exec-stmt($stmt);
  }

  method apply-counter-cache-on-create {
    for %!belongs-tos.kv -> $name, $spec {
      next if self.is-polymorphic-assoc($name);
      my $col = self.assoc-counter-cache-column($spec);
      next unless $col;
      my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
      my $fkey-val = (%!attrs{$fkey-col} // 0).Int;
      next unless $fkey-val;
      my $class = self.assoc-class-from-spec($spec);
      next if $class === Mu;
      my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
      self.counter-cache-bump($fkey-val, Utils.table-name($class), $col, $pkey-col, 1);
    }
  }

  method apply-counter-cache-on-update(%snapshot) {
    for %!belongs-tos.kv -> $name, $spec {
      next if self.is-polymorphic-assoc($name);
      my $col = self.assoc-counter-cache-column($spec);
      next unless $col;
      my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
      next unless %snapshot{$fkey-col}:exists;
      my $class = self.assoc-class-from-spec($spec);
      next if $class === Mu;
      my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
      my $target-table = Utils.table-name($class);
      my ($old-val, $new-val) = %snapshot{$fkey-col}.list;
      self.counter-cache-bump(($old-val // 0).Int, $target-table, $col, $pkey-col, -1);
      self.counter-cache-bump(($new-val // 0).Int, $target-table, $col, $pkey-col, 1);
    }
  }

  method apply-counter-cache-on-destroy {
    for %!belongs-tos.kv -> $name, $spec {
      next if self.is-polymorphic-assoc($name);
      my $col = self.assoc-counter-cache-column($spec);
      next unless $col;
      my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
      my $fkey-val = (%!attrs{$fkey-col} // 0).Int;
      next unless $fkey-val;
      my $class = self.assoc-class-from-spec($spec);
      next if $class === Mu;
      my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
      self.counter-cache-bump($fkey-val, Utils.table-name($class), $col, $pkey-col, -1);
    }
  }

  method touch-parent(Int:D $fkey-val, Str:D $target-table, Str:D $pkey-col, @cols) {
    return unless $fkey-val;
    return unless @cols.elems;
    my $now = DateTime.now;
    my %attrs;
    my %types;
    for @cols -> $col {
      %attrs{$col} = $now;
      %types{$col} = 'timestamp';
    }
    my %where = ($pkey-col => $fkey-val);
    my $stmt = $!db.build-update-where(
      :table($target-table), :%attrs, :%types, :%where,
    );
    $!db.exec-stmt($stmt);
  }

  method apply-touch-on-belongs-to {
    for %!belongs-tos.kv -> $name, $spec {
      next if self.is-polymorphic-assoc($name);
      my @cols = self.assoc-touch-columns($spec);
      next unless @cols.elems;
      my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
      my $fkey-val = (%!attrs{$fkey-col} // 0).Int;
      next unless $fkey-val;
      my $class = self.assoc-class-from-spec($spec);
      next if $class === Mu;
      my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
      my $target-table = Utils.table-name($class);
      my @target-fields = self.get-fields($target-table).map({ .name });
      my @existing = @cols.grep({ @target-fields.first(* eq $_).defined });
      self.touch-parent($fkey-val, $target-table, $pkey-col, @existing);
    }
  }

  method save(Bool :$validate = True, Bool :$touch = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
    return True if self.is-suppressed;
    self.apply-autosave-on-belongs-to;
    return False if $validate && !self.is-valid;
    self.update-foreign-keys;

    my Bool $was-new = $!id == 0;
    my Bool $locking = self.is-locking-enabled;
    my $lock-col = self.locking-column;
    my $prev-lock;
    my %snapshot;

    my $do-create = -> {
      return False unless self.do-before-creates;
      self.apply-sti-type;
      self.apply-secure-tokens;
      self.apply-secure-password;
      %!attrs<id> = $!id = $!db.create-object(self);
      self.apply-counter-cache-on-create;
      self.apply-touch-on-belongs-to;
      self.do-after-creates;
      True;
    };
    my $do-update = -> {
      return False unless self.do-before-updates;
      self.apply-secure-password;
      if $locking {
        my %types = @!fields.map({ .name => .type }).Hash;
        my $affected = $!db.update-records(
          :table(self.table-name),
          :attrs(self.attrs-to-persist),
          :%types,
          :where({ id => $!id, $lock-col => $prev-lock }),
        );
        if $affected == 0 {
          die X::StaleObjectError.new(model => self.WHAT.^name);
        }
      } else {
        $!db.update-object(self);
      }
      self.apply-counter-cache-on-update(%snapshot);
      self.apply-touch-on-belongs-to;
      self.do-after-updates;
      True;
    };

    my $inner-save = -> {
      return False unless self.do-before-saves;
      self.touch-timestamps if $touch;

      if $locking && !$was-new {
        $prev-lock = (%!attrs-db{$lock-col} // 0).Int;
        %!attrs{$lock-col} = $prev-lock + 1;
      }

      for self.changed -> $name {
        %snapshot{$name} = [%!attrs-db{$name}, %!attrs{$name}];
      }

      my Bool $op-ok = $was-new
        ?? self.run-around-chain('create', $do-create)
        !! self.run-around-chain('update', $do-update);
      return False unless $op-ok;

      self.do-after-saves;
      self.update-db-attrs;
      %!previous-changes = %snapshot;
      %!will-change = ();
      $!was-new-record = $was-new;
      $!db.register-txn-callback(self, $was-new ?? 'create' !! 'update');
      True;
    };

    self.run-around-chain('save', $inner-save);
  }

  method update-foreign-keys {
    for $.belongs-tos.keys -> $key {
      next unless $.attrs{$key};
      if self.is-polymorphic-assoc($key) {
        my $record = $.attrs{$key};
        next unless $record ~~ Model;
        $.attrs{$key ~ '_id'}   = $record.id;
        $.attrs{$key ~ '_type'} = $record.polymorphic-name;
        $.attrs{$key}:delete;
      }
      else {
        my $spec = $.belongs-tos{$key};
        my $assoc-class = self.assoc-class-from-spec($spec);
        if $assoc-class !=== Mu && $.attrs{$key} ~~ $assoc-class {
          my $fkey-col = self.assoc-fkey-from-spec($spec, $key ~ '_id');
          my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
          my $record = $.attrs{$key};
          $.attrs{$fkey-col} = $pkey-col eq 'id' ?? $record.id !! $record.attrs{$pkey-col};
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
    my $ok = self.update-columns(%attrs);
    self.do-after-touches if $ok;
    $ok;
  }

  method increment(Str:D $name, Numeric:D $n = 1) {
    %!attrs{$name} = (%!attrs{$name} // 0) + $n;
    self;
  }

  method increment-bang(Str:D $name, Numeric:D $n = 1) {
    self.increment($name, $n);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
  }

  method decrement(Str:D $name, Numeric:D $n = 1) {
    self.increment($name, -$n);
  }

  method decrement-bang(Str:D $name, Numeric:D $n = 1) {
    self.decrement($name, $n);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
  }

  method toggle(Str:D $name) {
    %!attrs{$name} = !%!attrs{$name};
    self;
  }

  method toggle-bang(Str:D $name) {
    self.toggle($name);
    self.update-attribute($name, %!attrs{$name}) or self.raise-invalid;
    self;
  }

  method save-bang {
    self.save or self.raise-invalid;
    self;
  }

  method update-bang(%attrs) {
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

  multi method create-bang(%attrs) {
    my %record = 'attrs' => %attrs;
    my $obj = self.new(:id(0), :%record);
    $obj.save-bang;
    $obj;
  }

  multi method create-bang {
    self.create-bang({});
  }

  multi method build(%attrs) {
    my %record = 'attrs' => %attrs;
    self.new(:id(0), :%record);
  }

  multi method build {
    self.build({});
  }

  method is-valid(Str :$context) {
    !self.is-invalid(:$context);
  }

  method is-invalid(Str :$context) {
    $!errors = Errors.new;
    self.do-before-validations;
    my $ctx = $context // $!validation-context // ($!id == 0 ?? 'create' !! 'update');
    $!validators.validate($!db, self, :context($ctx));
    self.validate-belongs-tos;
    self.do-after-validations;
    $!errors.errors.elems.so;
  }

  method validate-belongs-tos {
    for %!belongs-tos.kv -> $name, $spec {
      my $record = %!attrs{$name};

      if $record && $record ~~ Model && self.assoc-validate-flag($spec) {
        unless $record.is-valid {
          my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
          my $field = self.get-field($name) // self.get-field($fkey-col);
          if $field {
            my $message = 'is invalid';
            $!errors.push(Error.new(:$field, :$message, :type<invalid>));
          }
        }
      }

      next if self.is-belongs-to-optional($name);

      my $present = False;

      if %!attrs{$name}:exists && %!attrs{$name}.defined && %!attrs{$name} ~~ Model {
        $present = True;
      }

      if !$present && self.is-polymorphic-assoc($name) {
        my $id   = %!attrs{$name ~ '_id'};
        my $type = %!attrs{$name ~ '_type'};
        $present = True if $id && $type;
      }
      elsif !$present {
        my $fkey-col = self.assoc-fkey-from-spec($spec, $name ~ '_id');
        $present = True if (%!attrs{$fkey-col} // 0) != 0;

        if !$present {
          for %!belongs-tos.kv -> $sibling-name, $sibling-spec {
            next if $sibling-name eq $name;
            next if self.is-polymorphic-assoc($sibling-name);
            my $sibling-fkey = self.assoc-fkey-from-spec($sibling-spec, $sibling-name ~ '_id');
            next unless $sibling-fkey eq $fkey-col;
            my $sibling-record = %!attrs{$sibling-name};
            if $sibling-record && $sibling-record ~~ Model {
              $present = True;
              last;
            }
          }
        }
      }

      next if $present;

      my $field = self.get-field($name);
      next unless $field;
      my $template = 'must exist';
      my $message = Message.build(:$template, :obj(self), :$field);
      my $e = Error.new(:$field, :$message, :type<blank>);
      $!errors.push($e);
    }
  }

  method apply-autosave-on-belongs-to {
    for %!belongs-tos.kv -> $name, $spec {
      next if self.is-polymorphic-assoc($name);
      my $record = %!attrs{$name};
      next unless $record && $record ~~ Model;
      my $setting = self.assoc-autosave($spec);
      my $is-new = $record.id == 0;
      my $should;
      given $setting {
        when Bool:D { $should = $_ }
        default     { $should = $is-new }
      }
      next unless $should;
      $record.save;
    }
  }

  method validate(Str:D $name, Hash:D $params) {
    my $klass = self.WHAT;
    my $field = self.get-field($name);
    if $field !~~ Field { say 'Field "' ~ $name ~ '" does not exist'; die }

    my $v = Validator.new(:$klass, :$field, :$params);
    $!validators.validators.push($v);
  }

  multi method validates(@names, Hash:D $params) {
    for @names -> $name {
      next if $name eq '';
      if $params<associated> {
        self.validates-associated($name, $params);
      } else {
        self.validate($name, $params);
      }
    }
  }

  multi method validates(Str:D $name, Hash:D $params) {
    self.validates([$name], $params);
  }

  multi method validates(*@names, *%params) {
    self.validates(@names.list, %params.Hash);
  }

  method validates-with($validator, *%options) {
    my $klass = self.WHAT;
    my $wv = WithValidator.new(:$klass, :$validator, options => %options.Hash);
    $!validators.with-validators.push($wv);
  }

  multi method validates-each(@names, Block:D $block, %params = {}) {
    my $klass = self.WHAT;
    my @fields = @names.map(*.Str);
    my $ev = EachValidator.new(:$klass, :@fields, :$block, params => %params);
    $!validators.each-validators.push($ev);
  }

  multi method validates-each(Str:D $name, Block:D $block, %params = {}) {
    self.validates-each([$name], $block, %params);
  }

  multi method validates-each(*@names, :&block!, *%opts) {
    self.validates-each(@names.list, &block, %opts.Hash);
  }

  multi method validates-associated(Str:D $name, Hash:D $params = {}) {
    my $klass = self.WHAT;
    my $av = AssociatedValidator.new(:$klass, :$name, :$params);
    $!validators.associated.push($av);
  }

  multi method validates-associated(*@names) {
    self.validates-associated($_, {}) for @names;
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
    self.db.count-records(:$table, :%where);
  }

  multi method count(Hash:D $params) {
    my $table = Utils.table-name(self);
    my %where = $params;
    self.db.count-records(:$table, :%where);
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
    return False unless self.check-dependent-restrictions;

    my $do-destroy = -> {
      return False unless self.do-before-destroys;
      self.apply-dependent-actions;
      self.apply-counter-cache-on-destroy;
      self.apply-touch-on-belongs-to;
      self.delete;
      self.do-after-destroys;
      $!db.register-txn-callback(self, 'destroy');
      True;
    };
    self.run-around-chain('destroy', $do-destroy);
  }

  method check-dependent-restrictions(--> Bool) {
    for %!has-manys.kv -> $name, $spec {
      my $strategy = self.assoc-dependent($spec);
      next unless $strategy;
      next if self.assoc-spec-has($spec, 'through');
      next unless $strategy eq 'restrict-with-error' | 'restrict-with-exception';
      next unless self.dependent-many-has-children($name, $spec);
      if $strategy eq 'restrict-with-exception' {
        die X::DeleteRestrictionError.new(:model(self.WHAT.^name), :association($name));
      }
      self.add-restrict-error($name);
      return False;
    }
    for %!has-ones.kv -> $name, $spec {
      my $strategy = self.assoc-dependent($spec);
      next unless $strategy;
      next if self.assoc-spec-has($spec, 'through');
      next unless $strategy eq 'restrict-with-error' | 'restrict-with-exception';
      next unless self.dependent-one-has-child($name, $spec);
      if $strategy eq 'restrict-with-exception' {
        die X::DeleteRestrictionError.new(:model(self.WHAT.^name), :association($name));
      }
      self.add-restrict-error($name);
      return False;
    }
    True;
  }

  method apply-dependent-actions {
    for %!has-manys.kv -> $name, $spec {
      my $strategy = self.assoc-dependent($spec);
      next unless $strategy;
      next if self.assoc-spec-has($spec, 'through');
      given $strategy {
        when 'destroy'    { self.dependent-destroy-children($name, $spec, :many) }
        when 'delete-all' { self.dependent-delete-children($name, $spec)         }
        when 'nullify'    { self.dependent-nullify-children($name, $spec)        }
      }
    }
    for %!has-ones.kv -> $name, $spec {
      my $strategy = self.assoc-dependent($spec);
      next unless $strategy;
      next if self.assoc-spec-has($spec, 'through');
      given $strategy {
        when 'destroy'    { self.dependent-destroy-children($name, $spec, :!many) }
        when 'delete-all' { self.dependent-delete-children($name, $spec)          }
        when 'nullify'    { self.dependent-nullify-children($name, $spec)         }
      }
    }
    for %!belongs-tos.kv -> $name, $spec {
      my $strategy = self.assoc-dependent($spec);
      next unless $strategy;
      next if self.is-polymorphic-assoc($name);
      given $strategy {
        when 'destroy' {
          my $parent = self."$name"();
          $parent.destroy if $parent.defined;
        }
        when 'delete' | 'delete-all' {
          my $parent = self."$name"();
          $parent.delete if $parent.defined;
        }
      }
    }
  }

  method dependent-many-has-children(Str:D $name, \spec --> Bool) {
    my @records = self."$name"().list;
    @records.elems > 0;
  }

  method dependent-one-has-child(Str:D $name, \spec --> Bool) {
    my $record = self."$name"();
    $record.defined.so;
  }

  method add-restrict-error(Str:D $assoc) {
    my $field = Field.new(:name('base'), :type('association'));
    my $message = 'Cannot delete record because dependent ' ~ $assoc ~ ' exist';
    $!errors.push(Error.new(:$field, :$message, :type<restrict-dependent-destroy>));
  }

  method dependent-destroy-children(Str:D $name, \spec, Bool:D :$many) {
    if $many {
      for self."$name"().list -> $child { $child.destroy }
    } else {
      my $child = self."$name"();
      $child.destroy if $child.defined;
    }
  }

  method dependent-delete-children(Str:D $name, \spec) {
    my $class = self.assoc-class-from-spec(spec);
    return if $class === Mu;
    my Str $target-table = Utils.table-name($class);
    if self.assoc-spec-has(spec, 'as') {
      my $as-name = ~self.assoc-spec-value(spec, 'as');
      my $type-name = self.polymorphic-name;
      my $id-col = $as-name ~ '_id';
      my $type-col = $as-name ~ '_type';
      my $stmt = $!db.sanitize-sql-array([
        "DELETE FROM $target-table WHERE $id-col = ? AND $type-col = ?",
        $!id, $type-name,
      ]);
      $!db.exec-stmt($stmt);
    } else {
      my $fkey-col = self.assoc-fkey-from-spec(spec, Utils.base-name(self.fkey-name));
      my $pkey-col = self.assoc-pkey-from-spec(spec, 'id');
      my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
      my $stmt = $!db.sanitize-sql-array([
        "DELETE FROM $target-table WHERE $fkey-col = ?",
        $pkey-val,
      ]);
      $!db.exec-stmt($stmt);
    }
  }

  method dependent-nullify-children(Str:D $name, \spec) {
    my $class = self.assoc-class-from-spec(spec);
    return if $class === Mu;
    my Str $target-table = Utils.table-name($class);
    if self.assoc-spec-has(spec, 'as') {
      my $as-name = ~self.assoc-spec-value(spec, 'as');
      my $type-name = self.polymorphic-name;
      my $id-col = $as-name ~ '_id';
      my $type-col = $as-name ~ '_type';
      my $stmt = $!db.sanitize-sql-array([
        "UPDATE $target-table SET $id-col = NULL, $type-col = NULL WHERE $id-col = ? AND $type-col = ?",
        $!id, $type-name,
      ]);
      $!db.exec-stmt($stmt);
    } else {
      my $fkey-col = self.assoc-fkey-from-spec(spec, Utils.base-name(self.fkey-name));
      my $pkey-col = self.assoc-pkey-from-spec(spec, 'id');
      my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
      my $stmt = $!db.sanitize-sql-array([
        "UPDATE $target-table SET $fkey-col = NULL WHERE $fkey-col = ?",
        $pkey-val,
      ]);
      $!db.exec-stmt($stmt);
    }
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

  method lock-bang($mode = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
    die "lock-bang: record has no id (call save first)" unless $!id;
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
      self.lock-bang($mode);
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

  method becomes-bang($klass) {
    my $new = self.becomes($klass);
    my $column = $klass.inheritance-column;
    if $new.has-attribute($column) {
      $new.write-attribute($column, $klass.sti-name);
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
