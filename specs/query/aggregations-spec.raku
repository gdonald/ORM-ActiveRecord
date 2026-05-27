use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AgGame is Model {
  method table-name { 'games' }
}

describe 'aggregations', {
  before-each {
    AgGame.destroy-all;
    AgGame.create({name => 'Chess', year => 1500});
    AgGame.create({name => 'Go',    year => 2200});
    AgGame.create({name => 'Poker', year => 1810});
    AgGame.create({name => 'Magic', year => 1993});
  }

  after-each {
    AgGame.destroy-all;
  }

  context 'scalar aggregations on the whole table', {
    it 'sums the column', {
      expect(AgGame.sum('year')).to.eq(1500 + 2200 + 1810 + 1993);
    }

    it 'returns the minimum', {
      expect(AgGame.minimum('year')).to.eq(1500);
    }

    it 'returns the maximum', {
      expect(AgGame.maximum('year')).to.eq(2200);
    }

    it 'returns the average', {
      my $avg = AgGame.average('year');

      expect($avg.defined && $avg.Numeric == (1500 + 2200 + 1810 + 1993) / 4).to.be-truthy;
    }
  }

  context 'scalar aggregations on a relation', {
    it 'honors WHERE for sum', {
      expect(AgGame.where({name => 'Chess'}).sum('year')).to.eq(1500);
    }

    it 'honors WHERE for minimum', {
      expect(AgGame.where({name => 'Go'}).minimum('year')).to.eq(2200);
    }

    it 'honors WHERE for maximum', {
      expect(AgGame.where({name => 'Poker'}).maximum('year')).to.eq(1810);
    }

    it 'honors WHERE for average', {
      expect(AgGame.where({name => 'Magic'}).average('year')).to.eq(1993);
    }
  }

  context 'empty relation defaults', {
    it 'sum returns 0', {
      expect(AgGame.where({name => 'Nothing'}).sum('year')).to.eq(0);
    }

    it 'minimum is Nil', {
      expect(AgGame.where({name => 'Nothing'}).minimum('year').defined).to.be-falsy;
    }

    it 'maximum is Nil', {
      expect(AgGame.where({name => 'Nothing'}).maximum('year').defined).to.be-falsy;
    }

    it 'average is Nil', {
      expect(AgGame.where({name => 'Nothing'}).average('year').defined).to.be-falsy;
    }
  }

  context 'count with a column', {
    before-each {
      AgGame.create({name => 'Senet', year => Nil});
    }

    it 'Model.count counts all rows', {
      expect(AgGame.count).to.eq(5);
    }

    it 'Model.count(col) skips NULLs', {
      expect(AgGame.count('year')).to.eq(4);
    }
  }

  context 'count distinct via the relation flag', {
    it 'distinct.count(col) collapses dupes', {
      my $dup = AgGame.create({name => 'Chess', year => 1700});

      expect(AgGame.distinct.count('name')).to.eq(4);

      $dup.destroy;
    }
  }

  context 'calculate dispatcher', {
    it 'sums', {
      expect(AgGame.calculate('sum', 'year')).to.eq(1500 + 2200 + 1810 + 1993);
    }

    it 'averages case-insensitively', {
      expect(AgGame.calculate('AVG', 'year')).to.eq((1500 + 2200 + 1810 + 1993) / 4);
    }

    it 'mins', {
      expect(AgGame.calculate('min', 'year')).to.eq(1500);
    }

    it 'aliases Maximum', {
      expect(AgGame.calculate('Maximum', 'year')).to.eq(2200);
    }

    it 'counts without col', {
      expect(AgGame.calculate('count')).to.eq(4);
    }
  }

  context 'grouped aggregations', {
    before-each {
      AgGame.create({name => 'Chess', year => 1700});
    }

    it 'group.sum returns per-group totals', {
      my %by-name-sum = AgGame.group('name').sum('year');

      expect(%by-name-sum<Chess>).to.eq(1500 + 1700);
    }

    it 'group.sum has per-group entries', {
      my %by-name-sum = AgGame.group('name').sum('year');

      expect(%by-name-sum<Go>).to.eq(2200);
    }

    it 'group.sum has one entry per group', {
      my %by-name-sum = AgGame.group('name').sum('year');

      expect(%by-name-sum.elems).to.eq(4);
    }

    it 'group.maximum picks per group', {
      my %by-name-max = AgGame.group('name').maximum('year');

      expect(%by-name-max<Chess>).to.eq(1700);
    }

    it 'group.minimum picks per group', {
      my %by-name-min = AgGame.group('name').minimum('year');

      expect(%by-name-min<Chess>).to.eq(1500);
    }

    it 'group.average is per-group mean', {
      my %by-name-avg = AgGame.group('name').average('year');

      expect(%by-name-avg<Chess>.Num).to.eq(((1500 + 1700) / 2).Num);
    }
  }

  context 'having', {
    before-each {
      AgGame.create({name => 'Chess', year => 1700});
    }

    it 'hash form filters groups', {
      my %big = AgGame.group('name').having({ 'count(*)' => 2..* }).count;

      expect(%big.elems == 1 && %big<Chess> == 2).to.be-truthy;
    }

    it 'hash form on aggregate expression', {
      my %big2 = AgGame.group('name').having({ 'MIN(year)' => 2000..* }).count;

      expect(%big2.elems == 1 && %big2<Go> == 1).to.be-truthy;
    }
  }

  context 'pluck of SQL expressions', {
    it 'plucks UPPER(name)', {
      my @upper = AgGame.where({name => 'Go'}).pluck('UPPER(name)');

      expect(@upper.elems == 1 && @upper[0] eq 'GO').to.be-truthy;
    }

    it 'plucks qualified column', {
      my @qualified = AgGame.where({name => 'Go'}).pluck('games.year');

      expect(@qualified.elems == 1 && @qualified[0] == 2200).to.be-truthy;
    }
  }

  context 'none short-circuits aggregations', {
    it 'none.sum is 0', {
      expect(AgGame.none.sum('year')).to.eq(0);
    }

    it 'none.maximum is Nil', {
      expect(AgGame.none.maximum('year').defined).to.be-falsy;
    }

    it 'none.group.count is an empty hash', {
      expect(AgGame.none.group('name').count.elems).to.eq(0);
    }
  }
}
