use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'first / last with N', {
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

  context 'class-level first(N)', {
    it 'returns N rows', {
      my @firsts = User.first(2);

      expect(@firsts.elems).to.eq(2);
    }

    it 'returns rows ordered by id ASC', {
      my @firsts = User.first(2);

      expect(@firsts[0].id == $alice.id && @firsts[1].id == $bob.id).to.be-truthy;
    }
  }

  context 'class-level last(N)', {
    it 'returns N rows', {
      my @lasts = User.last(2);

      expect(@lasts.elems).to.eq(2);
    }

    it 'returns the last N rows in ASC order', {
      my @lasts = User.last(2);

      expect(@lasts[0].id == $carol.id && @lasts[1].id == $dave.id).to.be-truthy;
    }
  }

  it 'Model.first still returns one row', {
    expect(User.first.id).to.eq($alice.id);
  }

  it 'Model.last still returns one row', {
    expect(User.last.id).to.eq($dave.id);
  }

  it 'first(N) with N > rows returns all', {
    my @all-firsts = User.first(99);

    expect(@all-firsts.elems).to.eq(4);
  }

  it 'first(0) returns empty', {
    expect(User.first(0).elems).to.eq(0);
  }

  it 'last(0) returns empty', {
    expect(User.last(0).elems).to.eq(0);
  }

  it 'relation.first(N) respects WHERE', {
    my @rel-firsts = User.where({fname => ['Alice', 'Bob', 'Carol']}).first(2);

    expect(@rel-firsts.elems == 2 && @rel-firsts[0].id == $alice.id && @rel-firsts[1].id == $bob.id).to.be-truthy;
  }

  it 'relation.last(N) respects WHERE and returns ASC', {
    my @rel-lasts = User.where({fname => ['Alice', 'Bob', 'Carol']}).last(2);

    expect(@rel-lasts.elems == 2 && @rel-lasts[0].id == $bob.id && @rel-lasts[1].id == $carol.id).to.be-truthy;
  }

  it 'first(N) honors a custom order', {
    my @ordered-firsts = User.order('fname DESC').first(2);

    expect(@ordered-firsts.elems == 2 && @ordered-firsts[0].fname eq 'Dave' && @ordered-firsts[1].fname eq 'Carol').to.be-truthy;
  }

  it 'last(N) reverses a custom order, returns trailing rows in original order', {
    my @ordered-lasts = User.order('fname').last(2);

    expect(@ordered-lasts.elems == 2
           && @ordered-lasts[0].fname eq 'Carol'
           && @ordered-lasts[1].fname eq 'Dave').to.be-truthy;
  }

  it 'first(N) on .none is empty', {
    expect(User.none.first(3).elems).to.eq(0);
  }
}
