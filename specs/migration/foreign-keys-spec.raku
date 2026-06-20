use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter      = DB.shared.adapter;
my $has-db       = $adapter.defined && $adapter.is-connected;
my $current      = $has-db ?? live-adapter-name($adapter) !! Str;
my $is-sqlite    = $current.defined && $current eq 'sqlite';
my $skip-reason  = !$has-db
  ?? 'no database connection available'
  !! ($is-sqlite ?? 'SQLite cannot add/drop FK constraints via ALTER TABLE; declare FKs in create-table instead' !! Str);
my $active       = $has-db && !$is-sqlite;

sub adapter-kind(--> Str) {
  given $adapter.^name {
    when /Pg/    { 'pg' }
    when /MySql/ { 'mysql' }
    default      { 'unknown' }
  }
}

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub fk-exists(Str:D $table, Str:D $name) {
  my $rows = do given adapter-kind() {
    when 'pg' {
      $adapter.exec("SELECT 1 FROM pg_constraint WHERE conname = '$name' AND contype = 'f'");
    }
    when 'mysql' {
      $adapter.exec(qq:to/SQL/);
        SELECT 1
          FROM information_schema.table_constraints
         WHERE table_schema = DATABASE()
           AND table_name = '$table'
           AND constraint_name = '$name'
           AND constraint_type = 'FOREIGN KEY'
        SQL
    }
  };
  ?$rows.elems;
}

sub fk-action(Str:D $table, Str:D $name, Str:D $kind) {
  given adapter-kind() {
    when 'pg' {
      my $col = $kind eq 'delete' ?? 'confdeltype' !! 'confupdtype';
      my @r = $adapter.exec("SELECT $col FROM pg_constraint WHERE conname = '$name'");
      return Nil unless @r.elems;
      my $code = @r[0][0].Str;
      given $code {
        when 'a' { 'NO ACTION' }
        when 'r' { 'RESTRICT' }
        when 'c' { 'CASCADE' }
        when 'n' { 'SET NULL' }
        when 'd' { 'SET DEFAULT' }
        default  { $code }
      }
    }
    when 'mysql' {
      my $col = $kind eq 'delete' ?? 'delete_rule' !! 'update_rule';
      my @r = $adapter.exec(qq:to/SQL/);
        SELECT $col
          FROM information_schema.referential_constraints
         WHERE constraint_schema = DATABASE()
           AND constraint_name = '$name'
        SQL
      @r.elems ?? @r[0][0].Str.uc !! Nil;
    }
  }
}

my @test-tables = <_fk_orders _fk_customers _ref_users _ref_posts>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateUsers is Migration {
  method change {
    self.create-table: '_ref_users', [ name => { :string, limit => 32 } ];
  }
}

class CreatePosts is Migration {
  method change {
    self.create-table: '_ref_posts', [ title => { :string, limit => 32 } ];
  }
}

class AddUserRefFk is Migration {
  method change {
    self.add-reference: '_ref_posts', 'user', foreign-key => True, to-table => '_ref_users';
  }
}

class CreateFkTables is Migration {
  method change {
    self.create-table: '_fk_customers', [ name => { :string, limit => 32 } ];
    self.create-table: '_fk_orders',    [ amount => { :integer } ];
    self.add-column:   '_fk_orders', :customer_id => { :integer };
  }
}

class AddOrderCustomerFk is Migration {
  method change {
    self.add-foreign-key: '_fk_orders', '_fk_customers',
      column    => 'customer_id',
      on-delete => 'cascade',
      on-update => 'restrict';
  }
}

class AddNamedFk is Migration {
  method change {
    self.add-foreign-key: '_fk_orders', '_fk_customers',
      column => 'customer_id',
      name   => 'orders_cust_fk';
  }
}

class AddPlainFk is Migration {
  method up {
    self.add-foreign-key: '_fk_orders', '_fk_customers', column => 'customer_id';
  }
  method down {
    self.remove-foreign-key: '_fk_orders', to-table => '_fk_customers', column => 'customer_id';
  }
}

class AddRemoveByName is Migration {
  method up {
    self.add-foreign-key: '_fk_orders', '_fk_customers',
      column => 'customer_id', name => 'fk_keep_me';
  }
  method down {
    self.remove-foreign-key: '_fk_orders', name => 'fk_keep_me';
  }
}

class AddPendingFk is Migration {
  method up {
    self.add-foreign-key: '_fk_orders', '_fk_customers',
      column   => 'customer_id',
      name     => 'pending_fk',
      validate => False;
  }
  method down {
    self.remove-foreign-key: '_fk_orders', name => 'pending_fk';
  }
}

my &group = $active ?? &describe !! &xdescribe;

group 'migration foreign keys', :order<defined>, {
  if !$active { pending $skip-reason // 'not applicable'; }

  before-all {
    if $active {
      cleanup-tables;
      CreateUsers.new.up;
      CreatePosts.new.up;
    }
  }

  after-all { if $active { cleanup-tables } }

  context 'add-reference foreign-key shorthand', :order<defined>, {
    my $fk-name-default = 'fk__ref_posts_user_id';

    context 'after up', :order<defined>, {
      before-all { if $active { AddUserRefFk.new.up } }

      it 'creates the FK with derived name', {
        expect(fk-exists('_ref_posts', $fk-name-default)).to.be-truthy;
      }
    }

    context 'after down', :order<defined>, {
      before-all { if $active { AddUserRefFk.new.down } }

      it 'removes the FK constraint', {
        expect(fk-exists('_ref_posts', $fk-name-default)).to.be-falsy;
      }
    }
  }

  context 'add-foreign-key with on-delete / on-update', :order<defined>, {
    before-all { if $active { CreateFkTables.new.up } }

    context 'after up', :order<defined>, {
      before-all { if $active { AddOrderCustomerFk.new.up } }

      it 'creates the FK with derived name', {
        expect(fk-exists('_fk_orders', 'fk__fk_orders_customer_id')).to.be-truthy;
      }

      it 'emits ON DELETE CASCADE', {
        expect(fk-action('_fk_orders', 'fk__fk_orders_customer_id', 'delete')).to.eq('CASCADE');
      }

      it 'emits ON UPDATE RESTRICT', {
        expect(fk-action('_fk_orders', 'fk__fk_orders_customer_id', 'update')).to.eq('RESTRICT');
      }
    }

    context 'after down (auto-inverts to remove-foreign-key)', :order<defined>, {
      before-all { if $active { AddOrderCustomerFk.new.down } }

      it 'removes the FK', {
        expect(fk-exists('_fk_orders', 'fk__fk_orders_customer_id')).to.be-falsy;
      }
    }
  }

  context 'add-foreign-key with explicit :name', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $active { AddNamedFk.new.up } }

      it 'honors the :name override', {
        expect(fk-exists('_fk_orders', 'orders_cust_fk')).to.be-truthy;
      }
    }

    context 'after down', :order<defined>, {
      before-all { if $active { AddNamedFk.new.down } }

      it 'removes the named FK', {
        expect(fk-exists('_fk_orders', 'orders_cust_fk')).to.be-falsy;
      }
    }
  }

  context 'remove-foreign-key by :to-table derives the name', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $active { AddPlainFk.new.up } }

      it 'creates the FK', {
        expect(fk-exists('_fk_orders', 'fk__fk_orders_customer_id')).to.be-truthy;
      }
    }

    context 'after down', :order<defined>, {
      before-all { if $active { AddPlainFk.new.down } }

      it 'drops the derived-name FK', {
        expect(fk-exists('_fk_orders', 'fk__fk_orders_customer_id')).to.be-falsy;
      }
    }
  }

  context 'remove-foreign-key by :name', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $active { AddRemoveByName.new.up } }

      it 'creates the named FK', {
        expect(fk-exists('_fk_orders', 'fk_keep_me')).to.be-truthy;
      }
    }

    context 'after down', :order<defined>, {
      before-all { if $active { AddRemoveByName.new.down } }

      it 'drops the FK', {
        expect(fk-exists('_fk_orders', 'fk_keep_me')).to.be-falsy;
      }
    }
  }

  context 'add-foreign-key with validate => False', :order<defined>, {
    before-all { if $active { AddPendingFk.new.up } }
    after-all  { if $active { AddPendingFk.new.down } }

    it 'creates the FK', {
      expect(fk-exists('_fk_orders', 'pending_fk')).to.be-truthy;
    }

    it 'runs validate-foreign-key without error', {
      expect({ Migration.new.validate-foreign-key('_fk_orders', 'pending_fk') }).not.to.raise-error;
    }
  }
}
