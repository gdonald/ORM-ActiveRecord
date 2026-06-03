use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

my @test-tables = < _cf_null _cf_uniq _cf_cmt >;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

# `null => False` on types that the PostgreSQL builder used to skip (it only
# emitted NOT NULL for integer / varchar before the unified null clause).
class CreateNotNull is Migration {
  method change {
    self.create-table: '_cf_null', [
      tag     => { :string, limit => 16 },     # nullable
      flag    => { :boolean, null => False },
      made_at => { :datetime, null => False },
    ];
  }
}

class CreateUnique is Migration {
  method change {
    self.create-table: '_cf_uniq', [
      email => { :string, limit => 64, unique => True },
    ];
  }
}

class CreateCommented is Migration {
  method change {
    self.create-table: '_cf_cmt', [
      note => { :string, limit => 16, comment => 'a note' },
    ];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration column features', :order<defined>, {
  before-all { cleanup-tables }
  after-all  { cleanup-tables }

  context 'null: False enforced on all types', :order<defined>, {
    before-all { CreateNotNull.new.up }

    it 'rejects a row that leaves NOT NULL boolean / datetime columns null', {
      expect({ $adapter.exec("INSERT INTO _cf_null (tag) VALUES ('x')") }).to.raise-error;
    }
  }

  context 'unique shorthand', :order<defined>, {
    before-all {
      CreateUnique.new.up;
      $adapter.exec(q{INSERT INTO _cf_uniq (email) VALUES ('a@b.com')});
    }

    it 'allows a distinct value', {
      expect({ $adapter.exec(q{INSERT INTO _cf_uniq (email) VALUES ('c@d.com')}) }).not.to.raise-error;
    }

    it 'rejects a duplicate value', {
      expect({ $adapter.exec(q{INSERT INTO _cf_uniq (email) VALUES ('a@b.com')}) }).to.raise-error;
    }
  }

  context 'column comment', :order<defined>, {
    it 'creates a commented column without error', {
      expect({ CreateCommented.new.up }).not.to.raise-error;
    }
  }
}
