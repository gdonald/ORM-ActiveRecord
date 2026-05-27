use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class ExUser is Model {
  method table-name { 'users' }
}

describe 'excluding', {
  my ($alice, $bob, $carol, $dave);

  before-each {
    ExUser.destroy-all;
    $alice = ExUser.create({fname => 'Alice', lname => 'A'});
    $bob   = ExUser.create({fname => 'Bob',   lname => 'B'});
    $carol = ExUser.create({fname => 'Carol', lname => 'C'});
    $dave  = ExUser.create({fname => 'Dave',  lname => 'D'});
  }

  after-each {
    ExUser.destroy-all;
  }

  context 'excluding(record)', {
    it 'drops one row', {
      my @no-bob = ExUser.excluding($bob).order('fname').all;

      expect(@no-bob.elems).to.eq(3);
    }

    it 'returns the rest', {
      my @no-bob = ExUser.excluding($bob).order('fname').all;

      expect(@no-bob.map({ .fname }).join(',')).to.eq('Alice,Carol,Dave');
    }
  }

  context 'excluding(records)', {
    it 'drops the listed rows', {
      my @two = ExUser.excluding($alice, $dave).order('fname').all;

      expect(@two.elems).to.eq(2);
    }

    it 'returns the rest', {
      my @two = ExUser.excluding($alice, $dave).order('fname').all;

      expect(@two.map({ .fname }).join(',')).to.eq('Bob,Carol');
    }
  }

  context 'excluding(@ids)', {
    it 'drops by id', {
      my @by-id = ExUser.excluding($bob.id, $carol.id).order('fname').all;

      expect(@by-id.elems).to.eq(2);
    }

    it 'returns the rest', {
      my @by-id = ExUser.excluding($bob.id, $carol.id).order('fname').all;

      expect(@by-id.map({ .fname }).join(',')).to.eq('Alice,Dave');
    }
  }

  it 'count honors excluding', {
    expect(ExUser.excluding($alice).count).to.eq(3);
  }

  context 'excluding chained off where', {
    it 'narrows after where', {
      my @after-filter = ExUser.where({lname => ['A', 'B', 'C']}).excluding($alice).order('fname').all;

      expect(@after-filter.elems).to.eq(2);
    }

    it 'where + excluding combine', {
      my @after-filter = ExUser.where({lname => ['A', 'B', 'C']}).excluding($alice).order('fname').all;

      expect(@after-filter.map({ .fname }).join(',')).to.eq('Bob,Carol');
    }
  }
}
