use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class SrEmployee is Model {
  method table-name { 'employees' }
  method fkey-name  { 'manager_id' }

  submethod BUILD {
    self.belongs-to: manager => %(class => SrEmployee, optional => True);
    self.has-many: subordinates => %(class => SrEmployee, foreign-key => 'manager_id');
  }
}

describe 'self-referential association', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves a top-level employee without a manager', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    expect($ceo.id).to.be-greater-than(0);
  }

  it 'gives a top-level employee manager_id = 0', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    expect($ceo.attrs<manager_id>).to.eq(0);
  }

  it 'saves a child with a manager', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
    expect($vp.id).to.be-greater-than(0);
  }

  it 'fills manager_id on save', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
    expect($vp.attrs<manager_id>).to.eq($ceo.id);
  }

  context 'belongs-to read-back', {
    it 'resolves to a defined instance', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
      my $fetched = SrEmployee.find($vp.id);

      expect($fetched.manager.defined).to.be-truthy;
    }

    it 'resolves to the right class', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
      my $fetched = SrEmployee.find($vp.id);

      expect($fetched.manager.WHAT === SrEmployee).to.be-truthy;
    }

    it 'returns the right row', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
      my $fetched = SrEmployee.find($vp.id);

      expect($fetched.manager.id).to.eq($ceo.id);
    }

    it 'round-trips attributes', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
      my $fetched = SrEmployee.find($vp.id);

      expect($fetched.manager.attrs<name>).to.eq('Alice');
    }
  }

  it 'returns Nil for belongs-to when manager_id is 0', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    expect($ceo.manager).to.be-nil;
  }

  context 'has-many subordinates', {
    it 'returns both reports', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      SrEmployee.create({name => 'Bob',   manager => $ceo});
      SrEmployee.create({name => 'Carol', manager => $ceo});

      expect($ceo.subordinates.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      SrEmployee.create({name => 'Bob',   manager => $ceo});
      SrEmployee.create({name => 'Carol', manager => $ceo});

      expect($ceo.subordinates.map(*.attrs<name>).sort.join(',')).to.eq('Bob,Carol');
    }
  }

  it 'leaf employee has no subordinates', {
    my $ceo = SrEmployee.create({name => 'Alice'});
    my $vp  = SrEmployee.create({name => 'Bob', manager => $ceo});
    expect($vp.subordinates.elems).to.eq(0);
  }

  context 'reassignment', {
    it 'leaves the old manager with one report', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp1 = SrEmployee.create({name => 'Bob',   manager => $ceo});
      SrEmployee.create({name => 'Carol', manager => $ceo});
      my $mgr = SrEmployee.create({name => 'Dave',  manager => $ceo});
      $vp1.update({manager => $mgr});

      expect(SrEmployee.find($ceo.id).subordinates.elems).to.eq(2);
    }

    it 'gives the new manager the reassigned subordinate', {
      my $ceo = SrEmployee.create({name => 'Alice'});
      my $vp1 = SrEmployee.create({name => 'Bob',   manager => $ceo});
      SrEmployee.create({name => 'Carol', manager => $ceo});
      my $mgr = SrEmployee.create({name => 'Dave',  manager => $ceo});
      $vp1.update({manager => $mgr});

      expect(SrEmployee.find($mgr.id).subordinates.elems).to.eq(1);
    }
  }
}
