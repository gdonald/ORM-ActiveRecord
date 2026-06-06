use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS orders');
  $adapter.ddl-create-table('orders', [
    status => { :integer, default => 0 },
    state  => { :string, limit => 20 },
    name   => { :string, limit => 40 },
  ]);
}

class Order is Model {
  method table-name { 'orders' }

  submethod BUILD {
    self.enum: 'status', { active => 0, archived => 9 };
    self.enum: 'state',  { open => 'open', closed => 'closed' };
  }
}

GLOBAL::<Order> := Order;

END { try $adapter.exec('DROP TABLE IF EXISTS orders') if $has-db }

sub raw-status(Int:D $id) { $adapter.exec("SELECT status FROM orders WHERE id = $id")[0][0] }

my &group = $has-db ?? &describe !! &xdescribe;

group 'model enums', :order<defined>, {
  before-each { Order.destroy-all }
  after-each  { Order.destroy-all }

  context 'reading and storing', :order<defined>, {
    it 'reads back the symbolic name', {
      expect(Order.create({ status => 'active' }).status).to.eq('active');
    }

    it 'stores the backing value in the column', {
      my $o = Order.create({ status => 'active' });
      expect(raw-status($o.id).Int).to.eq(0);
    }

    it 'stores a custom backing value', {
      my $o = Order.create({ status => 'archived' });
      expect(raw-status($o.id).Int).to.eq(9);
    }

    it 'normalises a directly-assigned backing value to its symbol', {
      expect(Order.create({ status => 9 }).status).to.eq('archived');
    }

    it 'reads the symbol back from a reloaded record', {
      my $o = Order.create({ status => 'active' });
      expect(Order.find($o.id).status).to.eq('active');
    }
  }

  context 'predicates', :order<defined>, {
    it 'is true for the current value', {
      expect(Order.create({ status => 'active' }).is-active).to.be-truthy;
    }

    it 'is false for another value', {
      expect(Order.create({ status => 'active' }).is-archived).to.be-falsy;
    }
  }

  context 'bang setter', :order<defined>, {
    it 'assigns the value', {
      my $o = Order.create({ status => 'active' });
      $o.archived-bang;
      expect($o.status).to.eq('archived');
    }

    it 'persists the value', {
      my $o = Order.create({ status => 'active' });
      $o.archived-bang;
      expect(Order.find($o.id).status).to.eq('archived');
    }
  }

  context 'class scopes', :order<defined>, {
    before-each {
      Order.create({ status => 'active', name => 'x' });
      Order.create({ status => 'active', name => 'y' });
      Order.create({ status => 'archived', name => 'z' });
    }

    it 'returns only rows with the scoped value', {
      expect(Order.active.all.elems).to.eq(2);
    }

    it 'returns its own rows for another value', {
      expect(Order.archived.all.elems).to.eq(1);
    }
  }

  context 'text backing', :order<defined>, {
    it 'persists the text backing value', {
      my $o = Order.create({ state => 'closed' });
      expect($adapter.exec("SELECT state FROM orders WHERE id = {$o.id}")[0][0]).to.eq('closed');
    }

    it 'reads back the symbol', {
      expect(Order.create({ state => 'closed' }).state).to.eq('closed');
    }

    it 'supports a text-backed predicate', {
      expect(Order.create({ state => 'closed' }).is-closed).to.be-truthy;
    }

    it 'supports a text-backed class scope', {
      Order.create({ state => 'closed' });
      expect(Order.closed.all.elems).to.eq(1);
    }
  }

  context 'value enumeration', :order<defined>, {
    it 'lists the symbols for an enum', {
      expect(Order.enum-values('status').sort.list).to.eq(('active', 'archived'));
    }
  }
}
