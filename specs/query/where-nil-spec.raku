use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WnGame is Model {
  method table-name { 'games' }
}

describe 'where with Nil', {
  before-each {
    WnGame.destroy-all;
    WnGame.create({name => 'Chess', year => 1500});
    WnGame.create({name => 'Go',    year => Nil});
    WnGame.create({name => Nil,     year => 1800});
    WnGame.create({name => 'Poker', year => 1810});
  }

  after-each {
    WnGame.destroy-all;
  }

  context 'Nil shorthand on a string column', {
    it 'finds NULL rows', {
      my @nameless = WnGame.where({name => Nil}).all;

      expect(@nameless.elems).to.eq(1);
    }

    it 'returned row has NULL name', {
      my @nameless = WnGame.where({name => Nil}).all;

      expect(@nameless[0].name).to.be-falsy;
    }
  }

  context 'Nil shorthand on an integer column', {
    it 'finds NULL', {
      my @yearless = WnGame.where({year => Nil}).all;

      expect(@yearless.elems).to.eq(1);
    }

    it 'returned row matches', {
      my @yearless = WnGame.where({year => Nil}).all;

      expect(@yearless[0].name).to.eq('Go');
    }
  }

  context 'where.not(col => Nil) emits IS NOT NULL', {
    it 'finds non-NULL rows', {
      my @named = WnGame.where.not({name => Nil}).order('name').all;

      expect(@named.elems).to.eq(3);
    }

    it 'returns correctly', {
      my @named = WnGame.where.not({name => Nil}).order('name').all;

      expect(@named.map({ .name }).join(',')).to.eq('Chess,Go,Poker');
    }
  }

  it 'count honors Nil shorthand', {
    expect(WnGame.where({name => Nil}).count).to.eq(1);
  }

  it 'count honors IS NOT NULL', {
    expect(WnGame.where.not({name => Nil}).count).to.eq(3);
  }
}
