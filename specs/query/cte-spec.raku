use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CtGame is Model {
  method table-name { 'games' }
}

describe 'CTE / with', {
  before-each {
    CtGame.destroy-all;
    CtGame.create({name => 'Chess', year => 1500});
    CtGame.create({name => 'Go',    year => 2200});
    CtGame.create({name => 'Poker', year => 1810});
    CtGame.create({name => 'Magic', year => 1993});
  }

  after-each {
    CtGame.destroy-all;
  }

  context 'with(name => relation)', {
    it 'returns outer-table rows', {
      my $cte = CtGame.where({name => ['Chess', 'Go']});
      my @from-cte = CtGame.with(recent => $cte).where({name => ['Chess', 'Go']}).order('year').all;

      expect(@from-cte.elems).to.eq(2);
    }

    it 'first row from CTE+outer query is Chess', {
      my $cte = CtGame.where({name => ['Chess', 'Go']});
      my @from-cte = CtGame.with(recent => $cte).where({name => ['Chess', 'Go']}).order('year').all;

      expect(@from-cte[0].name).to.eq('Chess');
    }

    it 'second row is Go', {
      my $cte = CtGame.where({name => ['Chess', 'Go']});
      my @from-cte = CtGame.with(recent => $cte).where({name => ['Chess', 'Go']}).order('year').all;

      expect(@from-cte[1].name).to.eq('Go');
    }
  }

  it 'CTE binds + outer binds combine without collision', {
    my @count = CtGame.with(early => CtGame.where({year => 1000..1900})).where({year => 1900..2200}).all;

    expect(@count.elems).to.eq(2);
  }

  it 'from(cte-alias) reads rows out of the CTE', {
    my @from-source = CtGame.with(filtered => CtGame.where({name => 'Go'}))
                          .from('filtered AS games', 'games').all;

    expect(@from-source.elems == 1 && @from-source[0].name eq 'Go').to.be-truthy;
  }

  it 'count works with a CTE', {
    expect(CtGame.with(early => CtGame.where({year => 1000..1900})).where({year => 1000..1900}).count).to.eq(2);
  }

  it 'sum works alongside a CTE', {
    expect(CtGame.with(yrs => CtGame.all).where({name => 'Go'}).sum('year')).to.eq(2200);
  }

  it 'with(name => "raw SQL") accepts a string sub-query', {
    my @raw = CtGame.with(allrows => 'SELECT * FROM games')
                  .from('allrows AS games', 'games')
                  .where({name => 'Magic'}).all;

    expect(@raw.elems == 1 && @raw[0].name eq 'Magic').to.be-truthy;
  }

  context 'with-recursive', {
    it 'yields recursive rows', {
      my @ints = CtGame.with-recursive(nums => q:to/SUB/).from('nums').pluck('nums.n');
        SELECT 1 AS n
        UNION ALL
        SELECT n + 1 FROM nums WHERE n < 4
        SUB

      expect(@ints.elems).to.eq(4);
    }

    it 'generates 1..4', {
      my @ints = CtGame.with-recursive(nums => q:to/SUB/).from('nums').pluck('nums.n');
        SELECT 1 AS n
        UNION ALL
        SELECT n + 1 FROM nums WHERE n < 4
        SUB

      expect(@ints.sort.join(',')).to.eq('1,2,3,4');
    }
  }

  it 'with() with no args dies', {
    expect({ CtGame.all.with() }).to.raise-error;
  }
}
