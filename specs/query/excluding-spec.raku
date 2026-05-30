use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'excluding', {
  my ($alice, $bob, $carol, $dave);

  before-each {
    User.destroy-all;
    $alice = User.create({fname => 'Alice', lname => 'A'});
    $bob   = User.create({fname => 'Bob',   lname => 'B'});
    $carol = User.create({fname => 'Carol', lname => 'C'});
    $dave  = User.create({fname => 'Dave',  lname => 'D'});
  }

  after-each {
    User.destroy-all;
  }

  context 'excluding(record)', {
    it 'drops one row', {
      my @no-bob = User.excluding($bob).order('fname').all;

      expect(@no-bob.elems).to.eq(3);
    }

    it 'returns the rest', {
      my @no-bob = User.excluding($bob).order('fname').all;

      expect(@no-bob.map({ .fname }).join(',')).to.eq('Alice,Carol,Dave');
    }
  }

  context 'excluding(records)', {
    it 'drops the listed rows', {
      my @two = User.excluding($alice, $dave).order('fname').all;

      expect(@two.elems).to.eq(2);
    }

    it 'returns the rest', {
      my @two = User.excluding($alice, $dave).order('fname').all;

      expect(@two.map({ .fname }).join(',')).to.eq('Bob,Carol');
    }
  }

  context 'excluding(@ids)', {
    it 'drops by id', {
      my @by-id = User.excluding($bob.id, $carol.id).order('fname').all;

      expect(@by-id.elems).to.eq(2);
    }

    it 'returns the rest', {
      my @by-id = User.excluding($bob.id, $carol.id).order('fname').all;

      expect(@by-id.map({ .fname }).join(',')).to.eq('Alice,Dave');
    }
  }

  it 'count honors excluding', {
    expect(User.excluding($alice).count).to.eq(3);
  }

  context 'excluding chained off where', {
    it 'narrows after where', {
      my @after-filter = User.where({lname => ['A', 'B', 'C']}).excluding($alice).order('fname').all;

      expect(@after-filter.elems).to.eq(2);
    }

    it 'where + excluding combine', {
      my @after-filter = User.where({lname => ['A', 'B', 'C']}).excluding($alice).order('fname').all;

      expect(@after-filter.map({ .fname }).join(',')).to.eq('Bob,Carol');
    }
  }
}
