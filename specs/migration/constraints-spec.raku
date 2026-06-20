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
my $is-pg        = $current.defined && $current eq 'pg';
my $skip-reason  = !$has-db
  ?? 'no database connection available'
  !! ($is-sqlite ?? 'SQLite cannot add/drop check / unique constraints via ALTER TABLE; declare them in create-table instead' !! Str);
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

sub check-exists(Str:D $table, Str:D $name) {
  my $rows = do given adapter-kind() {
    when 'pg' {
      $adapter.exec("SELECT 1 FROM pg_constraint WHERE conname = '$name' AND contype = 'c'");
    }
    when 'mysql' {
      $adapter.exec(qq:to/SQL/);
        SELECT 1
          FROM information_schema.table_constraints
         WHERE table_schema = DATABASE()
           AND table_name = '$table'
           AND constraint_name = '$name'
           AND constraint_type = 'CHECK'
        SQL
    }
  };
  ?$rows.elems;
}

sub unique-exists(Str:D $table, Str:D $name) {
  my $rows = do given adapter-kind() {
    when 'pg' {
      $adapter.exec("SELECT 1 FROM pg_constraint WHERE conname = '$name' AND contype = 'u'");
    }
    when 'mysql' {
      $adapter.exec(qq:to/SQL/);
        SELECT 1
          FROM information_schema.table_constraints
         WHERE table_schema = DATABASE()
           AND table_name = '$table'
           AND constraint_name = '$name'
           AND constraint_type = 'UNIQUE'
        SQL
    }
  };
  ?$rows.elems;
}

sub exclusion-exists(Str:D $table, Str:D $name) {
  return False unless adapter-kind() eq 'pg';
  my $rows = $adapter.exec("SELECT 1 FROM pg_constraint WHERE conname = '$name' AND contype = 'x'");
  ?$rows.elems;
}

my @test-tables = <_chk_products _uq_products _excl_reservations>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateChkProducts is Migration {
  method change {
    self.create-table: '_chk_products', [
      name  => { :string, limit => 32 },
      price => { :integer },
    ];
  }
}

class AddPriceCheck is Migration {
  method change {
    self.add-check-constraint: '_chk_products', 'price > 0',
      name => 'chk_products_price_positive';
  }
}

class AddPriceCheckDerivedName is Migration {
  method change {
    self.add-check-constraint: '_chk_products', 'price >= 0';
  }
}

class AddPendingCheck is Migration {
  method up {
    self.add-check-constraint: '_chk_products', 'price < 1000000',
      name     => 'chk_products_price_max',
      validate => False;
  }
  method down {
    self.remove-check-constraint: '_chk_products', name => 'chk_products_price_max';
  }
}

class CreateUqProducts is Migration {
  method change {
    self.create-table: '_uq_products', [
      tenant_id => { :integer },
      sku       => { :string, limit => 32 },
    ];
  }
}

class AddSkuUnique is Migration {
  method change {
    self.add-unique-constraint: '_uq_products',
      columns => <tenant_id sku>,
      name    => 'uq_products_tenant_sku';
  }
}

class AddSkuUniqueDerivedName is Migration {
  method change {
    self.add-unique-constraint: '_uq_products', columns => <sku>;
  }
}

class CreateExclReservations is Migration {
  method change {
    self.create-table: '_excl_reservations', [
      room_id => { :integer },
      starts  => { :integer },
      ends    => { :integer },
    ];
  }
}

class AddRoomExclusion is Migration {
  method up {
    self.add-exclusion-constraint: '_excl_reservations',
      'room_id WITH =',
      using => 'btree',
      name  => 'excl_reservations_room';
  }
  method down {
    self.remove-exclusion-constraint: '_excl_reservations', name => 'excl_reservations_room';
  }
}

my &group = $active ?? &describe !! &xdescribe;

group 'migration constraints', :order<defined>, {
  if !$active { pending $skip-reason // 'not applicable'; }

  before-all { if $active { cleanup-tables } }
  after-all  { if $active { cleanup-tables } }

  context 'check constraints', :order<defined>, {
    before-all { if $active { CreateChkProducts.new.up } }

    context 'add-check-constraint with explicit :name', :order<defined>, {
      context 'after up', :order<defined>, {
        before-all { if $active { AddPriceCheck.new.up } }

        it 'creates the CHECK constraint', {
          expect(check-exists('_chk_products', 'chk_products_price_positive')).to.be-truthy;
        }
      }

      context 'after down (auto-inverts to remove-check-constraint)', :order<defined>, {
        before-all { if $active { AddPriceCheck.new.down } }

        it 'removes the CHECK constraint', {
          expect(check-exists('_chk_products', 'chk_products_price_positive')).to.be-falsy;
        }
      }
    }

    context 'add-check-constraint with derived name', :order<defined>, {
      my $derived;

      before-all {
        if $active {
          AddPriceCheckDerivedName.new.up;
          $derived = $adapter.ref-default-check-name('_chk_products', 'price >= 0');
        }
      }

      it 'creates a CHECK with the derived name', {
        expect(check-exists('_chk_products', $derived)).to.be-truthy;
      }

      context 'after down', :order<defined>, {
        before-all { if $active { AddPriceCheckDerivedName.new.down } }

        it 'removes the CHECK by derived name', {
          expect(check-exists('_chk_products', $derived)).to.be-falsy;
        }
      }
    }

    context 'validate => False then validate-check-constraint', :order<defined>, {
      before-all { if $active { AddPendingCheck.new.up } }
      after-all  { if $active { AddPendingCheck.new.down } }

      it 'creates the CHECK constraint', {
        expect(check-exists('_chk_products', 'chk_products_price_max')).to.be-truthy;
      }

      it 'runs validate-check-constraint without error', {
        expect({ Migration.new.validate-check-constraint('_chk_products', 'chk_products_price_max') }).not.to.raise-error;
      }
    }
  }

  context 'unique constraints', :order<defined>, {
    before-all { if $active { CreateUqProducts.new.up } }

    context 'add-unique-constraint with explicit :name', :order<defined>, {
      context 'after up', :order<defined>, {
        before-all { if $active { AddSkuUnique.new.up } }

        it 'creates the UNIQUE constraint', {
          expect(unique-exists('_uq_products', 'uq_products_tenant_sku')).to.be-truthy;
        }
      }

      context 'after down', :order<defined>, {
        before-all { if $active { AddSkuUnique.new.down } }

        it 'removes the UNIQUE constraint', {
          expect(unique-exists('_uq_products', 'uq_products_tenant_sku')).to.be-falsy;
        }
      }
    }

    context 'add-unique-constraint with derived name', :order<defined>, {
      context 'after up', :order<defined>, {
        before-all { if $active { AddSkuUniqueDerivedName.new.up } }

        it 'creates the UNIQUE constraint with derived name', {
          expect(unique-exists('_uq_products', 'uq__uq_products_sku')).to.be-truthy;
        }
      }

      context 'after down', :order<defined>, {
        before-all { if $active { AddSkuUniqueDerivedName.new.down } }

        it 'removes the derived-name UNIQUE', {
          expect(unique-exists('_uq_products', 'uq__uq_products_sku')).to.be-falsy;
        }
      }
    }
  }

  my &excl-group = $is-pg ?? &context !! &xcontext;

  excl-group 'exclusion constraints (PostgreSQL only)', :order<defined>, {
    if !$is-pg { pending 'exclusion constraints are PostgreSQL-only'; }

    my Bool $excl-after-up   = False;
    my Bool $excl-after-down = True;

    before-all {
      if $is-pg {
        CreateExclReservations.new.up;
        AddRoomExclusion.new.up;
        $excl-after-up = exclusion-exists('_excl_reservations', 'excl_reservations_room');
        AddRoomExclusion.new.down;
        $excl-after-down = exclusion-exists('_excl_reservations', 'excl_reservations_room');
      }
    }

    it 'creates the EXCLUDE constraint on up', {
      expect($excl-after-up).to.be-truthy;
    }

    it 'removes the EXCLUDE constraint on down', {
      expect($excl-after-down).to.be-falsy;
    }
  }
}
