use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'where with array', {
  my ($alice, $bob, $carol, $dave);

  before-each {
    User.destroy-all;
    $alice = User.create({fname => 'Alice', lname => 'Anderson'});
    $bob   = User.create({fname => 'Bob',   lname => 'Brown'});
    $carol = User.create({fname => 'Carol', lname => 'Crane'});
    $dave  = User.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    User.destroy-all;
  }

  context 'array of strings emits IN', {
    it 'returns matching count', {
      my @some = User.where({fname => ['Alice', 'Carol']}).order('fname').all;

      expect(@some.elems).to.eq(2);
    }

    it 'returns matching rows', {
      my @some = User.where({fname => ['Alice', 'Carol']}).order('fname').all;

      expect(@some.map({ .fname }).join(',')).to.eq('Alice,Carol');
    }
  }

  context 'array of ints', {
    it 'finds the listed ids', {
      my @by-id = User.where({id => [$alice.id, $dave.id]}).order('id').all;

      expect(@by-id.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my @by-id = User.where({id => [$alice.id, $dave.id]}).order('id').all;

      expect(@by-id[0].fname eq 'Alice' && @by-id[1].fname eq 'Dave').to.be-truthy;
    }
  }

  it 'single-element array IN', {
    my @one = User.where({fname => ['Bob']}).all;

    expect(@one.elems == 1 && @one[0].fname eq 'Bob').to.be-truthy;
  }

  it 'empty array IN matches no rows', {
    my @none = User.where({fname => []}).all;

    expect(@none.elems).to.eq(0);
  }

  context 'where.not with array emits NOT IN', {
    it 'returns the rest count', {
      my @rest = User.where.not({fname => ['Alice', 'Carol']}).order('fname').all;

      expect(@rest.elems).to.eq(2);
    }

    it 'returns the rest', {
      my @rest = User.where.not({fname => ['Alice', 'Carol']}).order('fname').all;

      expect(@rest.map({ .fname }).join(',')).to.eq('Bob,Dave');
    }
  }

  it 'where.not on empty array matches all', {
    expect(User.where.not({fname => []}).count).to.eq(4);
  }

  it 'count honors IN', {
    expect(User.where({fname => ['Alice', 'Bob', 'Carol']}).count).to.eq(3);
  }

  it 'IN combined with scalar where', {
    my @combo = User.where({fname => ['Alice', 'Dave', 'Carol']}).where({lname => 'Davis'}).all;

    expect(@combo.elems == 1 && @combo[0].fname eq 'Dave').to.be-truthy;
  }

  it 'pluck respects IN', {
    my @names = User.where({id => [$bob.id, $carol.id]}).order('fname').pluck('fname');

    expect(@names.join(',')).to.eq('Bob,Carol');
  }
}
