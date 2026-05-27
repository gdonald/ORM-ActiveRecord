use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class RuUser is Model {
  method table-name { 'users' }
}

describe 'rewhere / unscope', {
  my ($alice, $bob, $carol);

  before-each {
    RuUser.destroy-all;
    $alice = RuUser.create({fname => 'Alice', lname => 'Anderson'});
    $bob   = RuUser.create({fname => 'Bob',   lname => 'Brown'});
    $carol = RuUser.create({fname => 'Carol', lname => 'Anderson'});
  }

  after-each {
    RuUser.destroy-all;
  }

  context 'rewhere replaces existing where on a column', {
    it 'returned one row', {
      my @rw = RuUser.where({fname => 'Alice'}).rewhere({fname => 'Bob'}).all;

      expect(@rw.elems).to.eq(1);
    }

    it 'swapped Alice for Bob', {
      my @rw = RuUser.where({fname => 'Alice'}).rewhere({fname => 'Bob'}).all;

      expect(@rw[0].fname).to.eq('Bob');
    }
  }

  context 'rewhere preserves untouched columns', {
    it 'returned one row', {
      my @rw2 = RuUser.where({fname => 'Alice', lname => 'Anderson'}).rewhere({fname => 'Carol'}).all;

      expect(@rw2.elems).to.eq(1);
    }

    it 'kept Anderson, swapped to Carol', {
      my @rw2 = RuUser.where({fname => 'Alice', lname => 'Anderson'}).rewhere({fname => 'Carol'}).all;

      expect(@rw2[0].fname eq 'Carol' && @rw2[0].lname eq 'Anderson').to.be-truthy;
    }
  }

  context 'rewhere also clears not-conditions for the same column', {
    it 'cleared the negation', {
      my @rw3 = RuUser.where.not({fname => 'Alice'}).rewhere({fname => 'Alice'}).all;

      expect(@rw3.elems).to.eq(1);
    }

    it 'flipped back to Alice', {
      my @rw3 = RuUser.where.not({fname => 'Alice'}).rewhere({fname => 'Alice'}).all;

      expect(@rw3[0].fname).to.eq('Alice');
    }
  }

  it 'unscope(:where) drops all conditions', {
    my @us-where = RuUser.where({fname => 'Alice'}).unscope(:where).all;

    expect(@us-where.elems).to.eq(3);
  }

  it 'unscope positional Str also clears where', {
    my @us-pos = RuUser.where({fname => 'Alice'}).unscope('where').all;

    expect(@us-pos.elems).to.eq(3);
  }

  context 'unscope on a single column', {
    it 'kept the other condition', {
      my @us-col = RuUser.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => 'fname').all;

      expect(@us-col.elems).to.eq(2);
    }

    it 'all remaining rows match the kept condition', {
      my @us-col = RuUser.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => 'fname').all;

      expect(@us-col.map({ .lname }).all eq 'Anderson').to.be-truthy;
    }
  }

  it 'unscope(<fname lname>) cleared both conditions', {
    my @us-cols = RuUser.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => <fname lname>).all;

    expect(@us-cols.elems).to.eq(3);
  }

  it 'unscope cleared the previous order', {
    my @us-order = RuUser.order('fname DESC').unscope(:order).order('id').all;

    expect(@us-order[0].id).to.eq($alice.id);
  }

  it 'unscope(:limit) drops limit', {
    expect(RuUser.limit(1).unscope(:limit).all.elems).to.eq(3);
  }

  it 'unscope(:offset) drops offset', {
    expect(RuUser.offset(2).unscope(:offset).all.elems).to.eq(3);
  }
}
