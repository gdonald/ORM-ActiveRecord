use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS vehicles');
  $adapter.ddl-create-table('vehicles', [
    type   => { :string, limit => 32 },
    name   => { :string, limit => 64 },
    wheels => { :integer, default => 0 },
  ]);

  $adapter.exec('DROP TABLE IF EXISTS gizmos');
  $adapter.ddl-create-table('gizmos', [
    kind  => { :string, limit => 32 },
    label => { :string, limit => 64 },
  ]);

  $adapter.exec('DROP TABLE IF EXISTS tools');
  $adapter.ddl-create-table('tools', [
    type => { :string, limit => 32 },
    name => { :string, limit => 64 },
  ]);
}

class Vehicle is Model { method table-name { 'vehicles' } }
class Car        is Vehicle { }
class Motorcycle is Vehicle { }
class SportsCar  is Car     { }

class Gizmo is Model { method table-name { 'gizmos' } }
class Widget2 is Gizmo { }

class Tool is Model { method table-name { 'tools' } }
class Hammer   is Tool   { }
class BallPeen is Hammer { }

class Catalog is Model { method table-name { 'gizmos' } }
class Vendor::Item is Catalog { }

GLOBAL::<Vehicle>    := Vehicle;
GLOBAL::<Car>        := Car;
GLOBAL::<Motorcycle> := Motorcycle;
GLOBAL::<SportsCar>  := SportsCar;
GLOBAL::<Gizmo>      := Gizmo;
GLOBAL::<Widget2>    := Widget2;
GLOBAL::<Tool>       := Tool;
GLOBAL::<Hammer>     := Hammer;
GLOBAL::<BallPeen>   := BallPeen;

Gizmo.inheritance-column('kind');
Tool.abstract-class(True);
Motorcycle.sti-name('moto');
Catalog.store-full-sti-class(False);

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS vehicles');
    try $adapter.exec('DROP TABLE IF EXISTS gizmos');
    try $adapter.exec('DROP TABLE IF EXISTS tools');
  }
}

describe 'STI hierarchy predicates', :order<defined>, {
  it 'marks the base as descending from active record', {
    expect(Vehicle.descends-from-active-record).to.be-truthy;
  }

  it 'marks a subclass as not descending from active record', {
    expect(Car.descends-from-active-record).to.be-falsy;
  }

  it 'marks a deeper subclass as not descending from active record', {
    expect(SportsCar.descends-from-active-record).to.be-falsy;
  }

  it 'reports an abstract class as abstract', {
    expect(Tool.abstract-class).to.be-truthy;
  }

  it 'treats the first concrete class under an abstract base as the STI root', {
    expect(Hammer.descends-from-active-record).to.be-truthy;
  }

  it 'treats a subclass of the concrete root as a subclass', {
    expect(BallPeen.descends-from-active-record).to.be-falsy;
  }
}

describe 'STI configuration', :order<defined>, {
  it 'defaults the inheritance column to type', {
    expect(Vehicle.inheritance-column).to.eq('type');
  }

  it 'allows a custom inheritance column', {
    expect(Gizmo.inheritance-column).to.eq('kind');
  }

  it 'inherits the custom inheritance column in a subclass', {
    expect(Widget2.inheritance-column).to.eq('kind');
  }

  it 'allows overriding the stored STI name', {
    expect(Motorcycle.sti-name).to.eq('moto');
  }

  it 'can turn off storing the full class name', {
    expect(Catalog.store-full-sti-class).to.be-falsy;
  }

  it 'drops the namespace from a short STI name', {
    expect(Vendor::Item.sti-name.contains('::')).to.be-falsy;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'STI persistence and reads', :order<defined>, {
  before-each { Vehicle.destroy-all; Gizmo.destroy-all; Hammer.destroy-all }
  after-each  { Vehicle.destroy-all; Gizmo.destroy-all; Hammer.destroy-all }

  it 'populates the type column on save', {
    my $car = Car.create({ name => 'Civic', wheels => 4 });
    expect($car.attrs<type>).to.eq(Car.sti-name);
  }

  it 'instantiates a base read as the row subclass', {
    Car.create({ name => 'Civic', wheels => 4 });
    Motorcycle.create({ name => 'Harley', wheels => 2 });
    my @all = Vehicle.all.perform;
    aggregate-failures {
      expect(@all.grep(* ~~ Car).elems).to.eq(1);
      expect(@all.grep(* ~~ Motorcycle).elems).to.eq(1);
    }
  }

  it 'scopes a subclass finder to its own rows', {
    Car.create({ name => 'Civic', wheels => 4 });
    Motorcycle.create({ name => 'Harley', wheels => 2 });
    expect(Car.all.perform.elems).to.eq(1);
  }

  it 'includes deeper descendant subclasses in a finder', {
    Car.create({ name => 'Civic', wheels => 4 });
    SportsCar.create({ name => 'GT', wheels => 4 });
    expect(Car.all.perform.elems).to.eq(2);
  }

  it 'round-trips an overridden STI name', {
    Motorcycle.create({ name => 'Harley', wheels => 2 });
    expect(Vehicle.all.perform[0] ~~ Motorcycle).to.be-truthy;
  }

  it 'reads dispatch on a custom inheritance column', {
    Widget2.create({ label => 'left' });
    expect(Gizmo.all.perform[0] ~~ Widget2).to.be-truthy;
  }

  it 'dispatches subclasses under an abstract base', {
    BallPeen.create({ name => 'forged' });
    expect(Hammer.all.perform[0] ~~ BallPeen).to.be-truthy;
  }

  it 'rewrites the type column on becomes-bang', {
    my $as-moto = Car.create({ name => 'x', wheels => 4 }).becomes-bang(Motorcycle);
    expect($as-moto.attrs<type>).to.eq(Motorcycle.sti-name);
  }
}
