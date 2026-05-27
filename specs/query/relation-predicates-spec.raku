use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS rp_widgets');
  $adapter.ddl-create-table('rp_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
}

class RpWidget is Model {
  method table-name { 'rp_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS rp_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'relation predicates', {
  before-each {
    RpWidget.destroy-all if $has-db;
  }

  context 'on an empty table', {
    it 'is-empty is true', {
      expect(RpWidget.is-empty).to.be-truthy;
    }

    it 'is-any is false', {
      expect(RpWidget.is-any).to.be-falsy;
    }

    it 'is-one is false', {
      expect(RpWidget.is-one).to.be-falsy;
    }

    it 'is-many is false', {
      expect(RpWidget.is-many).to.be-falsy;
    }
  }

  context 'with 1 row', {
    before-each {
      RpWidget.create({ name => 'Alpha', qty => 1 });
    }

    it 'is-empty is false', {
      expect(RpWidget.is-empty).to.be-falsy;
    }

    it 'is-any is true', {
      expect(RpWidget.is-any).to.be-truthy;
    }

    it 'is-one is true', {
      expect(RpWidget.is-one).to.be-truthy;
    }

    it 'is-many is false', {
      expect(RpWidget.is-many).to.be-falsy;
    }
  }

  context 'with 3 rows', {
    before-each {
      RpWidget.create({ name => 'Alpha', qty => 1 });
      RpWidget.create({ name => 'Beta',  qty => 2 });
      RpWidget.create({ name => 'Gamma', qty => 3 });
    }

    it 'is-many is true', {
      expect(RpWidget.is-many).to.be-truthy;
    }

    it 'is-one is false', {
      expect(RpWidget.is-one).to.be-falsy;
    }

    it 'is-any is true', {
      expect(RpWidget.is-any).to.be-truthy;
    }

    it 'is-empty is false', {
      expect(RpWidget.is-empty).to.be-falsy;
    }
  }

  context 'predicates on filtered relations', {
    before-each {
      RpWidget.create({ name => 'Alpha', qty => 1 });
      RpWidget.create({ name => 'Beta',  qty => 2 });
      RpWidget.create({ name => 'Gamma', qty => 3 });
    }

    it 'is-one on a 1-row WHERE', {
      expect(RpWidget.where({ qty => 1 }).is-one).to.be-truthy;
    }

    it 'is-many on a 2-row WHERE', {
      expect(RpWidget.where({ qty => [1, 2] }).is-many).to.be-truthy;
    }

    it 'is-empty on a no-match WHERE', {
      expect(RpWidget.where({ qty => 99 }).is-empty).to.be-truthy;
    }

    it 'is-any false on no-match WHERE', {
      expect(RpWidget.where({ qty => 99 }).is-any).to.be-falsy;
    }
  }

  context 'is-none', {
    it 'is true after .none', {
      expect(RpWidget.none.is-none).to.be-truthy;
    }

    it 'is false on the unscoped relation', {
      expect(RpWidget.is-none).to.be-falsy;
    }

    it 'stays false for an empty-result query that was not .none', {
      expect(RpWidget.where({ qty => 99 }).is-none).to.be-falsy;
    }
  }

  context '.none short-circuits', {
    it 'none.is-empty is True without querying', {
      expect(RpWidget.none.is-empty).to.be-truthy;
    }

    it 'none.is-any is False', {
      expect(RpWidget.none.is-any).to.be-falsy;
    }

    it 'none.is-one is False even when underlying SQL would match 1', {
      expect(RpWidget.none.is-one).to.be-falsy;
    }

    it 'none.is-many is False', {
      expect(RpWidget.none.is-many).to.be-falsy;
    }
  }

  it 'predicates do not mutate the relation', {
    RpWidget.create({ name => 'Alpha', qty => 1 });

    my $rel = RpWidget.where({ qty => 1 });
    my $sql-before = $rel.to-sql;
    $rel.is-empty;
    $rel.is-any;
    $rel.is-one;
    $rel.is-many;
    $rel.is-none;

    expect($rel.to-sql).to.eq($sql-before);
  }

  context 'return types', {
    it 'is-empty returns a Bool', {
      expect(RpWidget.is-empty).to.be-a(Bool);
    }

    it 'is-any returns a Bool', {
      expect(RpWidget.is-any).to.be-a(Bool);
    }

    it 'is-one returns a Bool', {
      expect(RpWidget.is-one).to.be-a(Bool);
    }

    it 'is-many returns a Bool', {
      expect(RpWidget.is-many).to.be-a(Bool);
    }

    it 'is-none returns a Bool', {
      expect(RpWidget.is-none).to.be-a(Bool);
    }
  }
}
