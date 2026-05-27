use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WrBook is Model {
  method table-name { 'books' }
}

describe 'where with range', {
  before-each {
    WrBook.destroy-all;
    my %defaults = sentences => 1, words => 1, periods => 1, commas => 1;
    WrBook.create({title => 'A', pages => 50,  |%defaults});
    WrBook.create({title => 'B', pages => 100, |%defaults});
    WrBook.create({title => 'C', pages => 200, |%defaults});
    WrBook.create({title => 'D', pages => 300, |%defaults});
    WrBook.create({title => 'E', pages => 400, |%defaults});
  }

  after-each {
    WrBook.destroy-all;
  }

  context 'inclusive range', {
    it 'matched 3 rows', {
      my @mid = WrBook.where({pages => 100..300}).order('pages').all;

      expect(@mid.elems).to.eq(3);
    }

    it 'returned correct rows', {
      my @mid = WrBook.where({pages => 100..300}).order('pages').all;

      expect(@mid.map({ .title }).join(',')).to.eq('B,C,D');
    }
  }

  context 'exclusive-max range (..^)', {
    it 'matched 2 rows', {
      my @half-open = WrBook.where({pages => 100..^300}).order('pages').all;

      expect(@half-open.elems).to.eq(2);
    }

    it 'returned B,C', {
      my @half-open = WrBook.where({pages => 100..^300}).order('pages').all;

      expect(@half-open.map({ .title }).join(',')).to.eq('B,C');
    }
  }

  context 'exclusive-min range (^..)', {
    it 'matched 2 rows', {
      my @lower-open = WrBook.where({pages => 100^..300}).order('pages').all;

      expect(@lower-open.elems).to.eq(2);
    }

    it 'returned C,D', {
      my @lower-open = WrBook.where({pages => 100^..300}).order('pages').all;

      expect(@lower-open.map({ .title }).join(',')).to.eq('C,D');
    }
  }

  context 'fully exclusive (^..^)', {
    it 'matched 1 row', {
      my @both-open = WrBook.where({pages => 100^..^300}).order('pages').all;

      expect(@both-open.elems).to.eq(1);
    }

    it 'returned C', {
      my @both-open = WrBook.where({pages => 100^..^300}).order('pages').all;

      expect(@both-open[0].title).to.eq('C');
    }
  }

  it 'count honors range', {
    expect(WrBook.where({pages => 100..300}).count).to.eq(3);
  }

  context 'where.not with range', {
    it 'excluded 3 rows', {
      my @outside = WrBook.where.not({pages => 100..300}).order('pages').all;

      expect(@outside.elems).to.eq(2);
    }

    it 'returned outliers', {
      my @outside = WrBook.where.not({pages => 100..300}).order('pages').all;

      expect(@outside.map({ .title }).join(',')).to.eq('A,E');
    }
  }

  it 'range AND scalar condition narrows', {
    my @combo = WrBook.where({pages => 100..400}).where({title => 'D'}).all;

    expect(@combo.elems == 1 && @combo[0].title eq 'D').to.be-truthy;
  }
}
