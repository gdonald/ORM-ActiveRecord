use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($name) {
  $adapter.get-fields(table => $name).map({ $_[0] }).list;
}

my @test-tables = <_rev_a _rev_b _rev_c _rev_revert>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class BareMigration is Migration {}

class CreateRevA is Migration {
  method change {
    self.create-table: '_rev_a', [
      name => { :string, limit => 32 },
    ];
  }
}

class CreateRevB is Migration {
  method change {
    self.create-table: '_rev_b', [
      name => { :string, limit => 32 },
    ];
  }
}

class AddRevBYear is Migration {
  method change {
    self.add-column: '_rev_b', :year => { :integer };
  }
}

class CreateAandC is Migration {
  method change {
    self.create-table: '_rev_a', [name => { :string }];
    self.create-table: '_rev_c', [name => { :string }];
  }
}

my @reversible-calls;

class ReversibleSides is Migration {
  method change {
    self.create-table: '_rev_a', [name => { :string }];

    self.reversible: -> $dir {
      $dir.up:   { @reversible-calls.push: 'UP'   };
      $dir.down: { @reversible-calls.push: 'DOWN' };
    };
  }
}

class CreateRevertTarget is Migration {
  method change {
    self.create-table: '_rev_revert', [name => { :string }];
  }
}

class RevertCreateTarget is Migration {
  method change {
    self.revert: -> {
      self.create-table: '_rev_revert', [name => { :string }];
    };
  }
}

class ExecuteIrreversible is Migration {
  method change {
    self.execute('SELECT 1');
  }
}

class LegacyStyle is Migration {
  method up   { self.create-table: '_rev_a', [name => { :string }] }
  method down { self.drop-table:   '_rev_a' }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration reversibility', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all { if $has-db { cleanup-tables } }
  after-all  { if $has-db { cleanup-tables } }

  context 'bare migration (no change method)', {
    it 'throws X::IrreversibleMigration on up', {
      expect({ BareMigration.new.up }).to.raise-error(X::IrreversibleMigration);
    }
  }

  context 'change with a single create-table', :order<defined>, {
    after-all { if $has-db { cleanup-tables } }

    context 'on up', :order<defined>, {
      before-all { if $has-db { CreateRevA.new.up } }

      it 'creates the table', {
        expect(table-exists('_rev_a')).to.be-truthy;
      }
    }

    context 'on down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { CreateRevA.new.down } }

      it 'drops the table', {
        expect(table-exists('_rev_a')).to.be-falsy;
      }
    }
  }

  context 'change with add-column', :order<defined>, {
    before-all { if $has-db { CreateRevB.new.up } }
    after-all  { if $has-db { cleanup-tables } }

    context 'on up', :order<defined>, {
      before-all { if $has-db { AddRevBYear.new.up } }

      it 'adds the column', {
        expect('year' (elem) column-names('_rev_b')).to.be-truthy;
      }
    }

    context 'on down (auto-inverts)', :order<defined>, {
      before-all { if $has-db { AddRevBYear.new.down } }

      it 'removes the column', {
        expect('year' (elem) column-names('_rev_b')).to.be-falsy;
      }
    }
  }

  context 'change with multiple create-table calls', :order<defined>, {
    after-all { if $has-db { cleanup-tables } }

    context 'on up', :order<defined>, {
      before-all { if $has-db { CreateAandC.new.up } }

      it 'creates all tables in declaration order', {
        expect(table-exists('_rev_a') && table-exists('_rev_c')).to.be-truthy;
      }
    }

    context 'on down (reverse order)', :order<defined>, {
      before-all { if $has-db { CreateAandC.new.down } }

      it 'drops both tables', {
        expect(!table-exists('_rev_a') && !table-exists('_rev_c')).to.be-truthy;
      }
    }
  }

  context 'reversible block inside change', :order<defined>, {
    after-all { if $has-db { cleanup-tables } }

    context 'on up', :order<defined>, {
      before-all {
        if $has-db {
          @reversible-calls = ();
          ReversibleSides.new.up;
        }
      }

      it 'runs the up block during up direction', {
        expect(@reversible-calls.join(',')).to.eq('UP');
      }

      it 'also runs create-table', {
        expect(table-exists('_rev_a')).to.be-truthy;
      }
    }

    context 'on down', :order<defined>, {
      before-all {
        if $has-db {
          @reversible-calls = ();
          ReversibleSides.new.down;
        }
      }

      it 'runs the down block during down direction', {
        expect(@reversible-calls.join(',')).to.eq('DOWN');
      }

      it 'auto-inverts the create-table', {
        expect(table-exists('_rev_a')).to.be-falsy;
      }
    }
  }

  context 'revert(block) inside change', :order<defined>, {
    before-all { if $has-db { CreateRevertTarget.new.up } }
    after-all  { if $has-db { cleanup-tables } }

    context 'baseline', {
      it 'creates the target table', {
        expect(table-exists('_rev_revert')).to.be-truthy;
      }
    }

    context 'on up (executes inverse of the block)', :order<defined>, {
      before-all { if $has-db { RevertCreateTarget.new.up } }

      it 'drops the target table', {
        expect(table-exists('_rev_revert')).to.be-falsy;
      }
    }

    context 'on down (re-runs the block forward)', :order<defined>, {
      before-all { if $has-db { RevertCreateTarget.new.down } }

      it 're-creates the target table', {
        expect(table-exists('_rev_revert')).to.be-truthy;
      }
    }
  }

  context 'execute inside change', :order<defined>, {
    it 'runs raw SQL on up', {
      expect({ ExecuteIrreversible.new.up }).not.to.raise-error;
    }

    it 'throws X::IrreversibleMigration on down', {
      expect({ ExecuteIrreversible.new.down }).to.raise-error(X::IrreversibleMigration);
    }
  }

  context 'legacy up/down style', :order<defined>, {
    after-all { if $has-db { cleanup-tables } }

    context 'on up', :order<defined>, {
      before-all { if $has-db { LegacyStyle.new.up } }

      it 'creates the table', {
        expect(table-exists('_rev_a')).to.be-truthy;
      }
    }

    context 'on down', :order<defined>, {
      before-all { if $has-db { LegacyStyle.new.down } }

      it 'drops the table', {
        expect(table-exists('_rev_a')).to.be-falsy;
      }
    }
  }
}
