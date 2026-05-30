use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::Employee;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'self-referential association', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves a top-level employee without a manager', {
    my $ceo = Employee.create({name => 'Alice'});
    expect($ceo.id).to.be-greater-than(0);
  }

  it 'gives a top-level employee manager_id = 0', {
    my $ceo = Employee.create({name => 'Alice'});
    expect($ceo.attrs<manager_id>).to.eq(0);
  }

  it 'saves a child with a manager', {
    my $ceo = Employee.create({name => 'Alice'});
    my $vp  = Employee.create({name => 'Bob', manager => $ceo});
    expect($vp.id).to.be-greater-than(0);
  }

  it 'fills manager_id on save', {
    my $ceo = Employee.create({name => 'Alice'});
    my $vp  = Employee.create({name => 'Bob', manager => $ceo});
    expect($vp.attrs<manager_id>).to.eq($ceo.id);
  }

  context 'belongs-to read-back', {
    it 'resolves to a defined instance', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp  = Employee.create({name => 'Bob', manager => $ceo});
      my $fetched = Employee.find($vp.id);

      expect($fetched.manager.defined).to.be-truthy;
    }

    it 'resolves to the right class', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp  = Employee.create({name => 'Bob', manager => $ceo});
      my $fetched = Employee.find($vp.id);

      expect($fetched.manager.WHAT === Employee).to.be-truthy;
    }

    it 'returns the right row', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp  = Employee.create({name => 'Bob', manager => $ceo});
      my $fetched = Employee.find($vp.id);

      expect($fetched.manager.id).to.eq($ceo.id);
    }

    it 'round-trips attributes', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp  = Employee.create({name => 'Bob', manager => $ceo});
      my $fetched = Employee.find($vp.id);

      expect($fetched.manager.attrs<name>).to.eq('Alice');
    }
  }

  it 'returns Nil for belongs-to when manager_id is 0', {
    my $ceo = Employee.create({name => 'Alice'});
    expect($ceo.manager).to.be-nil;
  }

  context 'has-many subordinates', {
    it 'returns both reports', {
      my $ceo = Employee.create({name => 'Alice'});
      Employee.create({name => 'Bob',   manager => $ceo});
      Employee.create({name => 'Carol', manager => $ceo});

      expect($ceo.subordinates.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $ceo = Employee.create({name => 'Alice'});
      Employee.create({name => 'Bob',   manager => $ceo});
      Employee.create({name => 'Carol', manager => $ceo});

      expect($ceo.subordinates.map(*.attrs<name>).sort.join(',')).to.eq('Bob,Carol');
    }
  }

  it 'leaf employee has no subordinates', {
    my $ceo = Employee.create({name => 'Alice'});
    my $vp  = Employee.create({name => 'Bob', manager => $ceo});
    expect($vp.subordinates.elems).to.eq(0);
  }

  context 'reassignment', {
    it 'leaves the old manager with one report', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp1 = Employee.create({name => 'Bob',   manager => $ceo});
      Employee.create({name => 'Carol', manager => $ceo});
      my $mgr = Employee.create({name => 'Dave',  manager => $ceo});
      $vp1.update({manager => $mgr});

      expect(Employee.find($ceo.id).subordinates.elems).to.eq(2);
    }

    it 'gives the new manager the reassigned subordinate', {
      my $ceo = Employee.create({name => 'Alice'});
      my $vp1 = Employee.create({name => 'Bob',   manager => $ceo});
      Employee.create({name => 'Carol', manager => $ceo});
      my $mgr = Employee.create({name => 'Dave',  manager => $ceo});
      $vp1.update({manager => $mgr});

      expect(Employee.find($mgr.id).subordinates.elems).to.eq(1);
    }
  }
}
