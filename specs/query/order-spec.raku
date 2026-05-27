use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class OrdUser is Model {
  method table-name { 'users' }
}

describe 'order', {
  before-each {
    OrdUser.destroy-all;
    OrdUser.create({fname => 'Alice', lname => 'Brown'});
    OrdUser.create({fname => 'Bob',   lname => 'Brown'});
    OrdUser.create({fname => 'Carol', lname => 'Anderson'});
    OrdUser.create({fname => 'Dave',  lname => 'Anderson'});
    OrdUser.create({fname => 'Eve',   lname => 'Carter'});
  }

  after-each {
    OrdUser.destroy-all;
  }

  context 'multi-column order: lname ASC then fname DESC', {
    it 'Anderson Dave first', {
      my @r = OrdUser.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[0].join(' ')).to.eq('Anderson Dave');
    }

    it 'Anderson Carol second', {
      my @r = OrdUser.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[1].join(' ')).to.eq('Anderson Carol');
    }

    it 'Brown Bob third', {
      my @r = OrdUser.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[2].join(' ')).to.eq('Brown Bob');
    }

    it 'Carter Eve last', {
      my @r = OrdUser.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[*-1].join(' ')).to.eq('Carter Eve');
    }
  }

  context 'expression order LOWER(fname) DESC', {
    it 'Eve first', {
      my @e = OrdUser.order('LOWER(fname) DESC').pluck('fname');

      expect(@e[0]).to.eq('Eve');
    }

    it 'Alice last', {
      my @e = OrdUser.order('LOWER(fname) DESC').pluck('fname');

      expect(@e[*-1]).to.eq('Alice');
    }
  }

  it 'named-arg direction descends', {
    my @h = OrdUser.order(:fname<desc>).pluck('fname');

    expect(@h[0] eq 'Eve' && @h[*-1] eq 'Alice').to.be-truthy;
  }

  it 'named-arg direction ascends', {
    my @h2 = OrdUser.order(:fname<asc>).pluck('fname');

    expect(@h2[0] eq 'Alice' && @h2[*-1] eq 'Eve').to.be-truthy;
  }

  it 'invalid order direction is rejected', {
    expect({ OrdUser.order(:fname<sideways>).all }).to.raise-error;
  }

  it 'reorder cleared previous order', {
    my @ro = OrdUser.order('fname').reorder('lname').pluck('lname');

    expect(@ro[0]).to.eq('Anderson');
  }

  it 'reorder works without prior order', {
    my @ro2 = OrdUser.reorder('fname DESC').pluck('fname');

    expect(@ro2[0]).to.eq('Eve');
  }

  it 'reorder with multi-column string form', {
    my @ro3 = OrdUser.order('fname').reorder('lname DESC', 'fname ASC').pluck('lname', 'fname');

    expect(@ro3[0].join(' ')).to.eq('Carter Eve');
  }

  it 'unscope(:order) clears reorder result', {
    my @us = OrdUser.reorder('fname DESC').unscope(:order).order('id').all;

    expect(@us[0].fname).to.eq('Alice');
  }

  context 'in-order-of', {
    it 'puts the listed values in the requested order', {
      my @io = OrdUser.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');

      expect(@io[0] eq 'Carol' && @io[1] eq 'Alice' && @io[2] eq 'Bob').to.be-truthy;
    }

    it 'does not filter by default', {
      my @io = OrdUser.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');

      expect(@io.elems).to.eq(5);
    }

    it 'leaves remaining rows after the listed ones', {
      my @io = OrdUser.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');
      my @io-set = @io[3..4].sort;

      expect(@io-set.elems).to.eq(2);
    }

    it 'composes with where', {
      my @io-w = OrdUser.where({lname => 'Anderson'}).in-order-of('fname', ['Dave', 'Carol']).pluck('fname');

      expect(@io-w.join(',')).to.eq('Dave,Carol');
    }

    it 'requires at least one value', {
      expect({ OrdUser.in-order-of('fname', []) }).to.raise-error;
    }
  }
}
