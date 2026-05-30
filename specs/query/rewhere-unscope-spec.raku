use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'rewhere / unscope', {
  my ($alice, $bob, $carol);

  before-each {
    User.destroy-all;
    $alice = User.create({fname => 'Alice', lname => 'Anderson'});
    $bob   = User.create({fname => 'Bob',   lname => 'Brown'});
    $carol = User.create({fname => 'Carol', lname => 'Anderson'});
  }

  after-each {
    User.destroy-all;
  }

  context 'rewhere replaces existing where on a column', {
    it 'returned one row', {
      my @rw = User.where({fname => 'Alice'}).rewhere({fname => 'Bob'}).all;

      expect(@rw.elems).to.eq(1);
    }

    it 'swapped Alice for Bob', {
      my @rw = User.where({fname => 'Alice'}).rewhere({fname => 'Bob'}).all;

      expect(@rw[0].fname).to.eq('Bob');
    }
  }

  context 'rewhere preserves untouched columns', {
    it 'returned one row', {
      my @rw2 = User.where({fname => 'Alice', lname => 'Anderson'}).rewhere({fname => 'Carol'}).all;

      expect(@rw2.elems).to.eq(1);
    }

    it 'kept Anderson, swapped to Carol', {
      my @rw2 = User.where({fname => 'Alice', lname => 'Anderson'}).rewhere({fname => 'Carol'}).all;

      expect(@rw2[0].fname eq 'Carol' && @rw2[0].lname eq 'Anderson').to.be-truthy;
    }
  }

  context 'rewhere also clears not-conditions for the same column', {
    it 'cleared the negation', {
      my @rw3 = User.where.not({fname => 'Alice'}).rewhere({fname => 'Alice'}).all;

      expect(@rw3.elems).to.eq(1);
    }

    it 'flipped back to Alice', {
      my @rw3 = User.where.not({fname => 'Alice'}).rewhere({fname => 'Alice'}).all;

      expect(@rw3[0].fname).to.eq('Alice');
    }
  }

  it 'unscope(:where) drops all conditions', {
    my @us-where = User.where({fname => 'Alice'}).unscope(:where).all;

    expect(@us-where.elems).to.eq(3);
  }

  it 'unscope positional Str also clears where', {
    my @us-pos = User.where({fname => 'Alice'}).unscope('where').all;

    expect(@us-pos.elems).to.eq(3);
  }

  context 'unscope on a single column', {
    it 'kept the other condition', {
      my @us-col = User.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => 'fname').all;

      expect(@us-col.elems).to.eq(2);
    }

    it 'all remaining rows match the kept condition', {
      my @us-col = User.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => 'fname').all;

      expect(@us-col.map({ .lname }).all eq 'Anderson').to.be-truthy;
    }
  }

  it 'unscope(<fname lname>) cleared both conditions', {
    my @us-cols = User.where({fname => 'Alice', lname => 'Anderson'}).unscope(where => <fname lname>).all;

    expect(@us-cols.elems).to.eq(3);
  }

  it 'unscope cleared the previous order', {
    my @us-order = User.order('fname DESC').unscope(:order).order('id').all;

    expect(@us-order[0].id).to.eq($alice.id);
  }

  it 'unscope(:limit) drops limit', {
    expect(User.limit(1).unscope(:limit).all.elems).to.eq(3);
  }

  it 'unscope(:offset) drops offset', {
    expect(User.offset(2).unscope(:offset).all.elems).to.eq(3);
  }
}
