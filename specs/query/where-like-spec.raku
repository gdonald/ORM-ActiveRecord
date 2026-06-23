use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::Game;
use ORM::ActiveRecord::Relation::Query::Like;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'where with LIKE', {
  before-each {
    Game.destroy-all;
    Game.create({name => 'Chess',    year => 1500});
    Game.create({name => 'Checkers', year => 1600});
    Game.create({name => 'Go',       year => 1700});
    Game.create({name => 'Poker',    year => 1800});
    Game.create({name => 'a_b',      year => 1900});
    Game.create({name => 'axb',      year => 2000});
  }

  after-each {
    Game.destroy-all;
  }

  context 'starts-with', {
    it 'matches rows with the leading text', {
      my @ch = Game.where({name => LikePredicate.starts-with('Ch')}).order('name').all;

      expect(@ch.map({ .name }).join(',')).to.eq('Checkers,Chess');
    }

    it 'anchors at the beginning', {
      expect(Game.where({name => LikePredicate.starts-with('he')}).count).to.eq(0);
    }
  }

  context 'ends-with', {
    it 'matches rows with the trailing text', {
      expect(Game.where({name => LikePredicate.ends-with('s')}).count).to.eq(2);
    }
  }

  context 'contains', {
    it 'matches a substring', {
      my @ok = Game.where({name => LikePredicate.contains('ok')}).all;

      expect(@ok[0].name).to.eq('Poker');
    }

    it 'honors the predicate in count', {
      expect(Game.where({name => LikePredicate.contains('e')}).count).to.eq(3);
    }

    it 'escapes wildcard characters in the value', {
      my @lit = Game.where({name => LikePredicate.contains('a_b')}).all;

      expect(@lit.map({ .name }).join(',')).to.eq('a_b');
    }
  }

  context 'where.not', {
    it 'emits NOT LIKE', {
      expect(Game.where.not({name => LikePredicate.starts-with('Ch')}).count).to.eq(4);
    }
  }
}
