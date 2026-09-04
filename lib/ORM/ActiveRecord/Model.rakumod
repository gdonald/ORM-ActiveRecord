
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
use ORM::ActiveRecord::Model::Discard;
use ORM::ActiveRecord::Model::DirtyTracking;
use ORM::ActiveRecord::Model::Finders;
use ORM::ActiveRecord::Model::Inheritance;
use ORM::ActiveRecord::Model::Normalization;
use ORM::ActiveRecord::Model::PrimaryKey;
use ORM::ActiveRecord::Model::RawSql;
use ORM::ActiveRecord::Model::Reflection;
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
  does ModelDiscard
  does ModelDirtyTracking
  does ModelFinders
  does ModelInheritance
  does ModelNormalization
  does ModelPrimaryKey
  does ModelRawSql
  does ModelReflection
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
  my %belongs-to-names-of;
  my %fkey-name-of;

  has DB $!db;
  has Errors $!errors;
  has Validators $!validators;

  has %.record is rw;
  has %.has-manys;
  has %.has-ones;
  has %.habtms;
  has %.belongs-tos;
  has %.nested-config;
  has @.nested-pending is rw;

  has Int $.id is rw;
  has @.fields of Field;
  has %.attrs;
  has %.attrs-db;
  has Bool $.is-readonly is rw = False;
  has Bool $.is-strict-loading is rw = False;
  has Bool $.is-stubbed is rw = False;
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

  has @.before-discards;
  has @.after-discards;
  has @.before-undiscards;
  has @.after-undiscards;

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
  has %.assoc-cache-key;

  my Scopes $.scopes;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD(Int:D :$!id, :%!record) {
    $!db = self.db;

    self.WHAT.register-sti;
    @!fields = self.get-fields(self.table-name);
    my $only = (%!record && %!record<fields>) ?? %!record<fields>.map(*.name).Set !! Nil;
    my $row  = (%!record && %!record<attrs>) ?? %!record<attrs> !! Nil;

    if $row && $!id {
      self!fill-attr-defaults(:$only, :skip($row));
      self.merge-attrs($row);
      self.update-db-attrs;
      $!was-found-from-db = True;
    } elsif $row {
      self.init-attrs(:$only);
      self.merge-attrs($row);
    } else {
      self.init-attrs(:$only);

      if $!id {
        self.get-attrs(:$!id);
        $!was-found-from-db = True;
      }
    }
  }

  method errors(--> Errors) {
    $!errors //= Errors.new(:model-name(self.^name));
  }

  method validators(--> Validators) {
    $!validators //= Validators.new;
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
    DB.current(name => self.connection-name);
  }

  method rebind-db(DB:D $db) {
    $!db = $db;
    self;
  }

  method FALLBACK(Str:D $name, *@rest) is raw {
    my $scope-class = self.WHAT;
    if $?CLASS.scopes.exists($name, $scope-class) {
      return $?CLASS.scopes.exec($name, $scope-class, |@rest);
    }

    # Every dynamic accessor below spells its affix with a hyphen and columns
    # are snake_case, so a hyphen-free name that is already an attribute is a
    # plain read. A name ending in `_id` still falls through, so the belongs-to
    # branch can resolve an unset foreign key from its loaded record.
    if self.DEFINITE && !$name.contains('-') && !$name.ends-with('_id') {
      with self.store-accessor-column($name) -> $column {
        %!attrs{$column} = %() unless %!attrs{$column} ~~ Associative;
        return-rw %!attrs{$column}{$name};
      }

      return-rw %!attrs{$name} if %!attrs{$name}:exists;
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

    if $name ~~ /_id$/ && %!attrs{$name} == 0 {
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

    return-rw %!attrs{$name} if %!attrs{$name}:exists;

    if %!has-manys{$name}:exists {
      my $spec = %!has-manys{$name};
      my $cache-key = self!assoc-owner-key($spec);
      if self.assoc-cached($name, $cache-key) {
        my $cached := %!assoc-cache{$name}<>;
        return $cached if $cached ~~ CollectionProxy;
        my $cached-class = self.assoc-class-from-spec($spec) // Mu:U;
        return self.wrap-collection(-> { $cached.list }, $name, $spec, $cached-class, @rest);
      }
      self.check-strict-loading($name, $spec);
      my $class = Mu:U;
      my $join-table = '';
      my $as-name = '';
      my $fkey-override = '';
      my $pkey-col = 'id';
      my @order;

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
          when 'order' { @order = self.assoc-order-columns($spec) }
          when 'source' | 'source-type' | 'disable-joins' | 'strict-loading' | 'autosave' | 'validate' | 'query-constraints' | 'scope' { }
          default { say 'Unknown has-many type ' ~ $spec; die }
        }
      }

      my Str $target-table = Utils.table-name($class);
      my @fields = self.get-fields($target-table);
      my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
      my $scope-block = self.assoc-scope-block($spec);

      my $fkey-name = $fkey-override || Utils.base-name(self.fkey-name);

      # Each shape of the association becomes a loader the proxy runs on first
      # use, plus (where a single relation expresses it) a way to build that
      # relation, so `count` and `find` can ask the database directly instead of
      # fetching every row.
      my &load;
      my &relate = Callable;

      if $as-name {
        my $type-name = self.polymorphic-name;
        my %where = ($as-name ~ '_id') => $pkey-val, ($as-name ~ '_type') => $type-name;

        &load = -> {
          my @records = $scope-block.defined
            ?? self.apply-assoc-scope($scope-block, Query.new(:$class, :params(%where)), @rest).all
            !! $!db.get-objects(:$class, :@fields, :table($target-table), :%where, :@order);
          self.attach-inverse(@records, $spec, $class);
          @records;
        };

        &relate = (-> { $class.where(%where).order(|@order) }) unless $scope-block.defined;
      }
      elsif !$join-table && self.assoc-spec-has($spec, 'query-constraints') {
        my @cols = self.assoc-spec-value($spec, 'query-constraints').list;
        my $natural-fkey = $fkey-override || Utils.base-name(self.fkey-name);
        my %where;
        for @cols -> $col {
          %where{$col} = $col eq $natural-fkey ?? $pkey-val !! %!attrs{$col};
        }

        &load = -> {
          my @records = $scope-block.defined
            ?? self.apply-assoc-scope($scope-block, Query.new(:$class, :params(%where)), @rest).all
            !! $!db.get-objects(:$class, :@fields, :table($target-table), :%where, :@order);
          self.attach-inverse(@records, $spec, $class);
          @records;
        };

        &relate = (-> { $class.where(%where).order(|@order) }) unless $scope-block.defined;
      }
      elsif $join-table && self.assoc-spec-has($spec, 'disable-joins') && so self.assoc-spec-value($spec, 'disable-joins') {
        &load = -> {
          my $select = $!db.sanitize-sql-array([
            "SELECT {Utils.to-foreign-key($target-table)} FROM $join-table WHERE $fkey-name = ?",
            $pkey-val,
          ]);
          my @ids = $!db.exec-stmt($select).map({ $_[0] }).grep(*.defined);
          my @records;

          if @ids.elems {
            @records = $scope-block.defined
              ?? self.apply-assoc-scope($scope-block, Query.new(:$class, :params({ id => @ids.list })), @rest).all
              !! $!db.get-objects(:$class, :@fields, :table($target-table), :where({ id => @ids }));
          }

          self.attach-inverse(@records, $spec, $class);
          @records;
        };
      }
      elsif $join-table && $scope-block.defined {
        &load = -> {
          my $select = $!db.sanitize-sql-array([
            "SELECT {Utils.to-foreign-key($target-table)} FROM $join-table WHERE $fkey-name = ?",
            $pkey-val,
          ]);
          my @ids = $!db.exec-stmt($select).map({ $_[0] }).grep(*.defined);
          my @records;

          if @ids.elems {
            @records = self.apply-assoc-scope($scope-block, Query.new(:$class, :params({ id => @ids.list })), @rest).all;
          }

          self.attach-inverse(@records, $spec, $class);
          @records;
        };
      }
      else {
        &load = -> {
          my @records = $scope-block.defined
            ?? self.apply-assoc-scope($scope-block, Query.new(:$class, :params({ $fkey-name => $pkey-val })), @rest).all
            !! $!db.get-objects(:$class, :@fields, :table($target-table), :$join-table, :where($fkey-name => $pkey-val), :@order);
          self.attach-inverse(@records, $spec, $class);
          @records;
        };

        unless $scope-block.defined || $join-table {
          &relate = -> { $class.where(($fkey-name => $pkey-val).Hash).order(|@order) };
        }
      }

      return self!hold-collection($name, $cache-key, &load, &relate, $spec, $class, @rest, $scope-block);
    }

    if %!has-ones{$name}:exists {
      my $spec = %!has-ones{$name};
      my $cache-key = self!assoc-owner-key($spec);
      return %!assoc-cache{$name} if self.assoc-cached($name, $cache-key);
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
        return self!hold-assoc($name, $cache-key, Nil, $scope-block, @rest) unless $obj.defined;
        self.attach-inverse-single($obj, $spec, $class);
        return self!hold-assoc($name, $cache-key, $obj, $scope-block, @rest);
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
        return self!hold-assoc($name, $cache-key, Nil, $scope-block, @rest) unless @objects.elems;
        my $only = @objects.first;
        self.attach-inverse-single($only, $spec, $class);
        return self!hold-assoc($name, $cache-key, $only, $scope-block, @rest);
      }

      my $obj;
      if $scope-block.defined {
        my $q = Query.new(:$class, :params({ $fkey-name => $pkey-val }));
        $q = self.apply-assoc-scope($scope-block, $q, @rest);
        $obj = $q.first;
      } else {
        $obj = $!db.get-object(:$class, :@fields, :$table, where => ($fkey-name => $pkey-val).Hash);
      }
      return self!hold-assoc($name, $cache-key, Nil, $scope-block, @rest) unless $obj.defined;
      self.attach-inverse-single($obj, $spec, $class);
      return self!hold-assoc($name, $cache-key, $obj, $scope-block, @rest);
    }

    # A habtm collection is not kept between reads: its join table is written
    # from both sides, so a link added or cleared through the other record
    # would leave a kept collection stale with nothing to invalidate it. The
    # preloader still fills the cache for an `includes` load.
    if %!habtms{$name}:exists {
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

    if %!belongs-tos{$name}:exists {
      my $spec = %!belongs-tos{$name};
      my $cache-key = self.is-polymorphic-assoc($name)
        ?? (%!attrs{$name ~ '_type'}, %!attrs{$name ~ '_id'})
        !! %!attrs{self.assoc-fkey-from-spec($spec, $name ~ '_id')};
      return %!assoc-cache{$name} if self.assoc-cached($name, $cache-key);
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
        return self!hold-assoc($name, $cache-key, $!db.get-object(:$class, :@fields, :$table, where => :$id), Block, @rest);
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
      return self!hold-assoc($name, $cache-key, $!db.get-object(:$class, :@fields, :$table, :%where), $scope-block, @rest);
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

  # `order` on an association, as a string or a list of them. Declaring it here
  # rather than through a `scope` block keeps the association memoizable and
  # keeps `count` a `SELECT COUNT(*)`, neither of which a scope allows.
  method assoc-order-columns(\spec) {
    return () unless self.assoc-spec-has(spec, 'order');
    my $v = self.assoc-spec-value(spec, 'order');
    given $v {
      when Positional { return $v.list.map(*.Str).list }
      default         { return (~$v,) }
    }
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
    Utils.tableize(self.^name);
  }

  method fkey-name {
    %fkey-name-of{self.^name} //= self.WHAT.raku.lc ~ '_id';
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

  # An association loaded through a direct read is kept, so a second read does
  # not requery. The value it was loaded for is kept with it (the owner's
  # primary key for a collection, the foreign key for a belongs-to), so writing
  # that attribute invalidates the entry without needing a hook on attribute
  # assignment. The preloader writes `assoc-cache` with no key, and those
  # entries stay valid until something clears them.
  #
  # A collection is kept as its wrapped proxy and handed back as the same
  # object, so a `push` or `delete` through the proxy is visible on the next
  # read. An association with a scope block or scope arguments is never kept:
  # its rows depend on the arguments of the call.
  method assoc-cached(Str:D $name, $key --> Bool) {
    return False unless %!assoc-cache{$name}:exists;
    return True unless %!assoc-cache-key{$name}:exists;
    %!assoc-cache-key{$name} eqv $key;
  }

  # Decontainerized on the way out: a collection stored in a hash slot comes
  # back itemized, and `my @rows = $record.pages` would then bind the whole
  # proxy as a single element.
  method assoc-cache-put(Str:D $name, $key, $value) {
    %!assoc-cache{$name}     = $value;
    %!assoc-cache-key{$name} = $key;
    $value<>;
  }

  method assoc-cache-clear(Str $name?) {
    with $name {
      %!assoc-cache{$name}:delete;
      %!assoc-cache-key{$name}:delete;
    } else {
      %!assoc-cache     = ();
      %!assoc-cache-key = ();
    }
    self;
  }

  method !assoc-owner-key(\spec) {
    my $pkey-col = self.assoc-pkey-from-spec(spec, 'id');
    $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
  }

  # An association that came back empty is not kept. Re-reading it is one cheap
  # query, and keeping it would hide a record created through another handle
  # between the two reads, which is the common order in a create-then-read.
  method !hold-collection(Str:D $name, $key, &load, &relate, $spec, Mu $class, @args, $scope-block) {
    my $keep = !($scope-block.defined || @args.elems);
    my $proxy := self.wrap-collection(&load, $name, $spec, $class, @args, :&relate, :$keep);
    self.assoc-cache-put($name, $key, $proxy) if $keep;
    $proxy;
  }

  method !hold-assoc(Str:D $name, $key, $value, $scope-block, @args) {
    return $value<> if $scope-block.defined || @args.elems;
    return $value<> unless $value.defined;
    return $value<> if $value ~~ Positional && !$value.elems;
    self.assoc-cache-put($name, $key, $value);
  }

  # The rows are fetched by `&load` the first time anything reifies the array,
  # so a proxy that is only counted or searched never fetches them. `%state`
  # is shared with the proxy so it can tell loaded from unloaded.
  method wrap-collection(&load, Str:D $name, $spec, Mu $class, @args, :&relate, Bool :$keep = False) {
    my @col;
    @col does CollectionProxy;
    @col.owner        = self;
    @col.spec         = $spec;
    @col.target-class = $class;
    @col.assoc-name   = $name;
    @col.args         = @args.Array;
    @col.relate       = &relate;
    @col.load         = &load;
    @col.load-state   = %( loaded => False, keep => $keep );
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
    self.assoc-cache-clear($name);
    $class.create(%a);
  }

  method has-one-create-bang(Str:D $name, %attrs) {
    my ($class, %a) = self.has-one-attrs($name, %attrs);
    self.assoc-cache-clear($name);
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
    self.assoc-cache-clear($assoc);
    True;
  }

  method habtm-remove(Str:D $assoc, Mu:D $record --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my $target-key = self.habtm-target-key($assoc);
    my %where = ($owner-key => $!id, $target-key => $record.id);
    $!db.delete-records(:table($join-table), :%where);
    self.assoc-cache-clear($assoc);
    True;
  }

  method habtm-clear(Str:D $assoc --> Bool) {
    my $join-table = self.habtm-join-table($assoc);
    my $owner-key  = Utils.base-name(self.fkey-name);
    my %where = ($owner-key => $!id).Hash;
    $!db.delete-records(:table($join-table), :%where);
    self.assoc-cache-clear($assoc);
    True;
  }

  # A record instantiated from a fetched row (`:$only` = its column names)
  # gets attrs only for the columns the query selected, so a narrowed
  # `select` load doesn't fake the missing columns with type defaults.
  method init-attrs(:$only) {
    self!fill-attr-defaults(:$only);
    self.update-db-attrs;
  }

  # A column the fetched row already carries is overwritten by `merge-attrs`,
  # so `:skip` leaves it out and the caller snapshots once after the merge.
  method !fill-attr-defaults(:$only, :$skip) {
    for $!db.get-field-defaults(:table(self.table-name)).kv -> $name, $value {
      next if $only.defined && $name ∉ $only;
      next if $skip.defined && ($skip{$name}:exists);
      %!attrs{$name} = $value;
    }
  }

  # Two column lookups rather than a walk of every column of the table with a
  # `given`/`when` per column, on every save.
  method touch-timestamps {
    my %columns := self.field-map;
    return unless (%columns<updated_at>:exists) || (%columns<created_at>:exists);

    my $now = DateTime.now;
    %!attrs<updated_at> = $now if %columns<updated_at>:exists;
    %!attrs<created_at> //= $now if $!id == 0 && (%columns<created_at>:exists);
  }

  method merge-attrs(Hash:D $attrs) {
    for $attrs.keys { %!attrs{$_} = self.blank-to-null($_, $attrs{$_}) }
  }

  # A blank string assigned to a non-text column means "no value", so it becomes
  # the typed null (NULL, or a DB default such as an auto-set timestamp). Text and
  # character columns keep the empty string. A blank form field thus casts to
  # null for datetime, numeric, and boolean attributes.
  method blank-to-null(Str:D $name, $value) {
    return $value unless $value.defined && $value ~~ Str && $value eq '';
    my $field = self.field-map{$name};
    return $value unless $field && $field.type.defined;
    return $value if $field.type ~~ /:i character | text | varchar | 'char' | string /;
    Nil;
  }

  method primary-key-where(--> Hash) {
    my %where;
    for self.WHAT.locating-columns -> $col {
      %where{$col} = $col eq 'id' ?? $!id !! %!attrs{$col};
    }
    %where;
  }

  method get-attrs(:$id) {
    my @fields = @!fields;
    my %where = self.WHAT.default-id-locating ?? (id => $id).Hash !! self.primary-key-where;
    %!attrs = $!db.get-record(:@fields, table => self.table-name, :%where);
    self.update-db-attrs;
  }

  method field-names {
    @!fields.map({ $_.name });
  }

  # One shallow copy rather than a write per column. Hydration calls this for
  # every row, and on a ten-column table the per-key loop measured about 9%
  # slower over 400 rows.
  method update-db-attrs {
    %!attrs-db := %!attrs.clone;
  }

  method locking-column(--> Str) { 'lock_version' }

  method is-locking-enabled(--> Bool) {
    so (self.field-map{self.locking-column}:exists);
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
      my %target-fields := $!db.get-field-map(:table($target-table));
      my @existing = @cols.grep({ %target-fields{$_}:exists });
      self.touch-parent($fkey-val, $target-table, $pkey-col, @existing);
    }
  }

  method save(Bool :$validate = True, Bool :$touch = True) {
    die X::ReadOnlyRecord.new(model => self.WHAT.^name) if $!is-readonly;
    die X::FrozenRecord.new(model => self.WHAT.^name)   if $!is-destroyed;
    return True if self.is-suppressed;
    self.extract-nested-attributes;
    self.apply-autosave-on-belongs-to;
    self.apply-normalizations;
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
      my $supplied = (%!attrs<id> // 0).Int;
      my $generated = $!db.create-object(self);
      %!attrs<id> = $!id = $supplied > 0 ?? $supplied !! $generated;
      self.apply-counter-cache-on-create;
      self.apply-touch-on-belongs-to;
      self.do-after-creates;
      True;
    };
    my $do-update = -> {
      return False unless self.do-before-updates;
      self.apply-secure-password;
      if $locking {
        my %types = self.field-types;
        my %where = self.WHAT.default-id-locating
          ?? %( id => $!id, $lock-col => $prev-lock )
          !! %( |self.primary-key-where, $lock-col => $prev-lock );
        my $affected = $!db.update-records(
          :table(self.table-name),
          :attrs(self.attrs-to-persist),
          :%types,
          :%where,
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
      self.apply-nested-pending;
      %!previous-changes = %snapshot;
      %!will-change = ();
      $!was-new-record = $was-new;
      $!db.register-txn-callback(self, $was-new ?? 'create' !! 'update');
      True;
    };

    if @!nested-pending.elems {
      my $result = False;
      $!db.transaction({ $result = self.run-around-chain('save', $inner-save) });
      return $result;
    }

    self.run-around-chain('save', $inner-save);
  }

  method update-foreign-keys {
    for $.belongs-tos.keys -> $key {
      next unless $.attrs{$key}:exists;

      # Assigning an undefined association clears its foreign key rather than
      # writing the association name as a column.
      unless $.attrs{$key}.defined {
        if self.is-polymorphic-assoc($key) {
          $.attrs{$key ~ '_id'}   = Nil;
          $.attrs{$key ~ '_type'} = Nil;
        }
        else {
          my $spec = $.belongs-tos{$key};
          my $fkey-col = self.assoc-fkey-from-spec($spec, $key ~ '_id');
          $.attrs{$fkey-col} = Nil;
        }
        $.attrs{$key}:delete;
        next;
      }

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
      %!attrs{$key} = self.blank-to-null($key, %attrs{$key});
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
    my $stmt = self.WHAT.default-id-locating
      ?? $!db.build-update(:$table, :id($!id), :%attrs, :%types)
      !! $!db.build-update-where(:$table, :%attrs, :%types, :where(self.primary-key-where));
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
    for self.errors.errors -> $e {
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
    $!errors = Errors.new(:model-name(self.^name));
    self.do-before-validations;
    my $ctx = $context // $!validation-context // ($!id == 0 ?? 'create' !! 'update');
    self.validators.validate($!db, self, :context($ctx));
    self.validate-belongs-tos;
    self.validate-nested-pending;
    self.do-after-validations;
    self.errors.errors.elems.so;
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
            self.errors.push(Error.new(:$field, :$message, :type<invalid>));
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
      my $message = Message.build(:default('must exist'), :type<required>, :obj(self), :$field);
      my $e = Error.new(:$field, :$message, :type<blank>);
      self.errors.push($e);
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

  # ---- nested attributes ----

  method accepts-nested-attributes-for(*@names, *%opts) {
    for @names -> $name {
      %!nested-config{~$name} = %opts;
    }
    self;
  }

  method nested-truthy($value --> Bool) {
    return False without $value;
    given $value {
      when Bool { return $value }
      when Numeric { return $value != 0 }
      default {
        my $s = (~$value).trim.lc;
        return False if $s eq '' | '0' | 'false' | 'f' | 'no' | 'off';
        return True;
      }
    }
  }

  method extract-nested-attributes {
    @!nested-pending = [];
    for %!nested-config.kv -> $name, %opts {
      my $key = $name ~ '-attributes';
      next unless %!attrs{$key}:exists;
      my $raw = %!attrs{$key};
      %!attrs{$key}:delete;
      self.build-nested-pending($name, %opts, $raw);
    }
  }

  method build-nested-pending(Str:D $name, %opts, $raw) {
    my Bool $is-many = %!has-manys{$name}:exists;
    my Bool $is-one  = %!has-ones{$name}:exists;
    return unless $is-many || $is-one;

    my $spec  = $is-many ?? %!has-manys{$name} !! %!has-ones{$name};
    my $class = self.assoc-class-from-spec($spec);
    return if $class === Mu;

    if $is-many {
      my @entries = $raw ~~ Positional ?? $raw.list !! ($raw,);

      if %opts<limit>:exists {
        my $limit = %opts<limit>.Int;
        die "accepts-nested-attributes-for $name: too many records (limit $limit)"
          if @entries.elems > $limit;
      }

      for @entries -> $entry {
        self.nested-op($name, $spec, $class, %opts, $entry.hash, :many);
      }
    } else {
      self.nested-op($name, $spec, $class, %opts, $raw.hash, :!many);
    }
  }

  method nested-op(Str:D $name, $spec, $class, %opts, %entry, Bool:D :$many) {
    my Bool $allow-destroy = so %opts<allow-destroy>;
    my Bool $update-only   = so %opts<update-only>;
    my Bool $marked = $allow-destroy && self.nested-truthy(%entry<_destroy>);

    my $id = (%entry<id> // 0).Int;

    my %clean;
    for %entry.kv -> $k, $v { %clean{$k} = $v unless $k eq '_destroy' }

    my $existing = $many ?? Nil !! self.nested-existing-one($name);

    if $marked {
      my $target;
      if $id { $target = $class.find($id) }
      elsif $existing.defined { $target = $existing }
      return without $target;
      @!nested-pending.push: %( :action<destroy>, :record($target), :assoc($name) );
      return;
    }

    if %opts<reject-if>:exists {
      my $pred = %opts<reject-if>;
      return if self.nested-rejected($pred, %clean);
    }

    %clean<id>:delete;

    if $existing.defined && $update-only {
      self.nested-assign($existing, %clean, $spec, $class);
      @!nested-pending.push: %( :action<update>, :record($existing), :assoc($name), :$spec );
    }
    elsif $id {
      my $rec = $class.find($id);
      self.nested-assign($rec, %clean, $spec, $class);
      @!nested-pending.push: %( :action<update>, :record($rec), :assoc($name), :$spec );
    }
    else {
      my $rec = $class.build(%clean);
      self.attach-inverse-single($rec, $spec, $class);
      @!nested-pending.push: %( :action<create>, :record($rec), :assoc($name), :$spec );
    }
  }

  method nested-assign($rec, %clean, $spec, $class) {
    for %clean.kv -> $k, $v { $rec.write-attribute($k, $v) }
    self.attach-inverse-single($rec, $spec, $class);
  }

  method nested-existing-one(Str:D $name) {
    return Nil if $!id == 0;
    my $child = self."$name"();
    $child.defined ?? $child !! Nil;
  }

  method nested-rejected($pred, %clean --> Bool) {
    return False without $pred;
    so $pred(%clean);
  }

  method validate-nested-pending {
    for @!nested-pending -> %op {
      next if %op<action> eq 'destroy';
      my $rec = %op<record>;
      next if $rec.is-valid;
      self.errors.add(%op<assoc>, 'invalid', message => 'is invalid');
    }
  }

  method apply-nested-pending {
    for @!nested-pending -> %op {
      my $rec = %op<record>;
      given %op<action> {
        when 'destroy' { $rec.destroy }
        default {
          my $spec = %op<spec>;
          my $fkey = self.assoc-fkey-from-spec($spec, Utils.base-name(self.fkey-name));
          my $pkey-col = self.assoc-pkey-from-spec($spec, 'id');
          my $pkey-val = $pkey-col eq 'id' ?? $!id !! %!attrs{$pkey-col};
          $rec.write-attribute($fkey, $pkey-val);
          $rec.save or die X::RecordInvalid.new(:record($rec), :messages($rec.errors.errors.map(*.message).list));
        }
      }
    }
    @!nested-pending = [];
  }

  method validate(Str:D $name, Hash:D $params) {
    my $klass = self.WHAT;
    my $field = self.get-field($name);
    if $field !~~ Field { say 'Field "' ~ $name ~ '" does not exist'; die }

    my $v = Validator.new(:$klass, :$field, :$params);
    self.validators.validators.push($v);
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
    self.validators.with-validators.push($wv);
  }

  multi method validates-each(@names, Block:D $block, %params = {}) {
    my $klass = self.WHAT;
    my @fields = @names.map(*.Str);
    my $ev = EachValidator.new(:$klass, :@fields, :$block, params => %params);
    self.validators.each-validators.push($ev);
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
    self.validators.associated.push($av);
  }

  multi method validates-associated(*@names) {
    self.validates-associated($_, {}) for @names;
  }

  method scope(Str:D $name, Block:D $block) {
    my $klass = self.WHAT;

    $?CLASS.scopes.register(Scope.new(:$klass, :$name, :$block));
  }

  method get-fields(Str:D $table) {
    $!db.get-field-objects(:$table);
  }

  # Which associations a model declares as belongs-to is fixed by the class, so
  # the names are derived from one instance and kept, rather than by building a
  # throwaway record for every relation that has to normalize its params.
  method belongs-to-names(--> Set) {
    %belongs-to-names-of{self.^name} //= self.new(:id(0)).belongs-tos.keys.Set;
  }

  method field-map(--> Hash) {
    $!db.get-field-map(:table(self.table-name));
  }

  method field-types(--> Hash) {
    $!db.get-field-types(:table(self.table-name));
  }

  method get-field(Str:D $name) {
    with self.field-map{$name} -> $field { return $field }
    with self.field-map{$name ~ '_id'} -> $field { return $field if $field.type eq 'integer' }
    Nil;
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
    self.errors.push(Error.new(:$field, :$message, :type<restrict-dependent-destroy>));
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
    my %where = self.WHAT.default-id-locating ?? (id => $!id).Hash !! self.primary-key-where;
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

# Declare a named scope as a method: `method published is scope { self.where(...) }`.
# The method works directly (Page.published) and is also registered per-class so
# it is introspectable and discoverable by name like a `self.scope(...)` scope.
multi sub trait_mod:<is>(Method:D $method, :$scope!) is export {
  # Mark the method so a relation can recognize it as a scope by introspection
  # (this survives precompilation, unlike the compile-time global registry).
  $method does IsScope;

  my $klass = $method.package;
  my $name  = $method.name;

  Scopes.register(
    Scope.new(:$klass, :$name, :block(-> |args { $klass."$name"(|args) }))
  );
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
