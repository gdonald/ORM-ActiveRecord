use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS cc_widgets');
  $adapter.ddl-create-table('cc_widgets', [
    name   => { :string, limit => 64 },
    qty    => { :integer, default => 0 },
    active => { :boolean, default => False },
  ]);
  $adapter.ddl-add-timestamps('cc_widgets');

  $adapter.exec('DROP TABLE IF EXISTS cc_vehicles');
  $adapter.ddl-create-table('cc_vehicles', [
    type => { :string, limit => 64 },
    name => { :string, limit => 64 },
  ]);
}

class CcWidget is Model {
  method table-name { 'cc_widgets' }
}

class CcVehicle is Model {
  method table-name { 'cc_vehicles' }
}

class CcCar is CcVehicle {
  method table-name { 'cc_vehicles' }
}

class CcTruck is CcVehicle {
  method table-name { 'cc_vehicles' }
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS cc_widgets');
    try $adapter.exec('DROP TABLE IF EXISTS cc_vehicles');
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'cloning and copying', {
  context 'dup of a persisted record', {
    my $w;
    my $d;

    before-each {
      $w = CcWidget.create({ name => 'orig', qty => 5, active => True });
      $d = $w.dup;
    }

    it 'yields a new record', {
      expect($d.is-new-record).to.be-truthy;
    }

    it 'is not persisted', {
      expect($d.is-persisted).to.be-falsy;
    }

    it 'has id == 0', {
      expect($d.id).to.eq(0);
    }

    it 'copies the name', {
      expect($d.name).to.eq('orig');
    }

    it 'copies the qty', {
      expect($d.qty).to.eq(5);
    }

    it 'copies active', {
      expect($d.active).to.eq(True);
    }

    it 'is a distinct instance from the original', {
      expect($d.WHICH).not.to.eq($w.WHICH);
    }

    it 'mutating the dup does not affect the original', {
      $d.name = 'cloned';

      expect($w.name).to.eq('orig');
    }
  }

  context 'dup of an unsaved record', {
    my $w;
    my $d;

    before-each {
      $w = CcWidget.build({ name => 'unsaved', qty => 9 });
      $d = $w.dup;
    }

    it 'yields a new record', {
      expect($d.is-new-record).to.be-truthy;
    }

    it 'carries the attrs', {
      expect($d.name).to.eq('unsaved');
    }
  }

  context 'dup save', {
    my $w;
    my $d;

    before-each {
      $w = CcWidget.create({ name => 'parent', qty => 1 });
      $d = $w.dup;
      $d.save;
    }

    it 'assigns a new id', {
      expect($d.id).to.be-greater-than(0);
    }

    it 'produces a different id from the original', {
      expect($d.id).not.to.eq($w.id);
    }
  }

  context 'clone', {
    my $w;
    my $c;

    before-each {
      $w = CcWidget.create({ name => 'cloneme', qty => 11 });
      $c = $w.clone;
    }

    it 'preserves the id', {
      expect($c.id).to.eq($w.id);
    }

    it 'preserves the name', {
      expect($c.name).to.eq('cloneme');
    }

    it 'is a distinct instance', {
      expect($c.WHICH).not.to.eq($w.WHICH);
    }

    it 'mutating the clone does not affect the original', {
      $c.name = 'changed';

      expect($w.name).to.eq('cloneme');
    }
  }

  context 'clone propagates readonly state', {
    it 'preserves the readonly flag', {
      my $w = CcWidget.create({ name => 'ro', qty => 1 });
      $w.make-readonly;

      my $c = $w.clone;

      expect($c.is-readonly).to.be-truthy;
    }
  }

  context 'becomes', {
    my $v;
    my $car;

    before-each {
      $v   = CcVehicle.create({ name => 'V1', type => 'CcVehicle' });
      $car = $v.becomes(CcCar);
    }

    it 'returns a CcCar', {
      expect($car).to.be-a(CcCar);
    }

    it 'returns also a CcVehicle', {
      expect($car).to.be-a(CcVehicle);
    }

    it 'preserves the id', {
      expect($car.id).to.eq($v.id);
    }

    it 'copies the attrs', {
      expect($car.name).to.eq('V1');
    }
  }

  context 'becomes-or-die sets the type column', {
    my $truck;

    before-each {
      my $v = CcVehicle.create({ name => 'V2', type => 'CcVehicle' });
      $truck = $v.becomes-or-die(CcTruck);
    }

    it 'returns a CcTruck', {
      expect($truck).to.be-a(CcTruck);
    }

    it 'writes the new class name to the type column', {
      expect($truck.read-attribute('type')).to.match(/'CcTruck'/);
    }
  }

  context 'becomes rejects non-Model targets', {
    it 'raises', {
      my $v = CcVehicle.create({ name => 'V3', type => 'CcVehicle' });

      expect({ $v.becomes(Int) }).to.raise-error;
    }
  }
}
