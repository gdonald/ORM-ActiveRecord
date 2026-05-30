use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'order', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Brown'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Anderson'});
    User.create({fname => 'Dave',  lname => 'Anderson'});
    User.create({fname => 'Eve',   lname => 'Carter'});
  }

  after-each {
    User.destroy-all;
  }

  context 'multi-column order: lname ASC then fname DESC', {
    it 'Anderson Dave first', {
      my @r = User.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[0].join(' ')).to.eq('Anderson Dave');
    }

    it 'Anderson Carol second', {
      my @r = User.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[1].join(' ')).to.eq('Anderson Carol');
    }

    it 'Brown Bob third', {
      my @r = User.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[2].join(' ')).to.eq('Brown Bob');
    }

    it 'Carter Eve last', {
      my @r = User.order('lname', 'fname DESC').pluck('lname', 'fname');

      expect(@r[*-1].join(' ')).to.eq('Carter Eve');
    }
  }

  context 'expression order LOWER(fname) DESC', {
    it 'Eve first', {
      my @e = User.order('LOWER(fname) DESC').pluck('fname');

      expect(@e[0]).to.eq('Eve');
    }

    it 'Alice last', {
      my @e = User.order('LOWER(fname) DESC').pluck('fname');

      expect(@e[*-1]).to.eq('Alice');
    }
  }

  it 'named-arg direction descends', {
    my @h = User.order(:fname<desc>).pluck('fname');

    expect(@h[0] eq 'Eve' && @h[*-1] eq 'Alice').to.be-truthy;
  }

  it 'named-arg direction ascends', {
    my @h2 = User.order(:fname<asc>).pluck('fname');

    expect(@h2[0] eq 'Alice' && @h2[*-1] eq 'Eve').to.be-truthy;
  }

  it 'invalid order direction is rejected', {
    expect({ User.order(:fname<sideways>).all }).to.raise-error;
  }

  it 'reorder cleared previous order', {
    my @ro = User.order('fname').reorder('lname').pluck('lname');

    expect(@ro[0]).to.eq('Anderson');
  }

  it 'reorder works without prior order', {
    my @ro2 = User.reorder('fname DESC').pluck('fname');

    expect(@ro2[0]).to.eq('Eve');
  }

  it 'reorder with multi-column string form', {
    my @ro3 = User.order('fname').reorder('lname DESC', 'fname ASC').pluck('lname', 'fname');

    expect(@ro3[0].join(' ')).to.eq('Carter Eve');
  }

  it 'unscope(:order) clears reorder result', {
    my @us = User.reorder('fname DESC').unscope(:order).order('id').all;

    expect(@us[0].fname).to.eq('Alice');
  }

  context 'in-order-of', {
    it 'puts the listed values in the requested order', {
      my @io = User.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');

      expect(@io[0] eq 'Carol' && @io[1] eq 'Alice' && @io[2] eq 'Bob').to.be-truthy;
    }

    it 'does not filter by default', {
      my @io = User.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');

      expect(@io.elems).to.eq(5);
    }

    it 'leaves remaining rows after the listed ones', {
      my @io = User.in-order-of('fname', ['Carol', 'Alice', 'Bob']).pluck('fname');
      my @io-set = @io[3..4].sort;

      expect(@io-set.elems).to.eq(2);
    }

    it 'composes with where', {
      my @io-w = User.where({lname => 'Anderson'}).in-order-of('fname', ['Dave', 'Carol']).pluck('fname');

      expect(@io-w.join(',')).to.eq('Dave,Carol');
    }

    it 'requires at least one value', {
      expect({ User.in-order-of('fname', []) }).to.raise-error;
    }
  }
}
