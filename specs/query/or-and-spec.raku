use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'or / and', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Crane'});
    User.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    User.destroy-all;
  }

  context 'or with two simple wheres', {
    it 'merges two relations into a disjunction', {
      my @or = User.where({fname => 'Alice'}).or(User.where({fname => 'Carol'})).order('fname').all;

      expect(@or.elems).to.eq(2);
    }

    it 'returned both alternates', {
      my @or = User.where({fname => 'Alice'}).or(User.where({fname => 'Carol'})).order('fname').all;

      expect(@or.map({ .fname }).join(',')).to.eq('Alice,Carol');
    }
  }

  context 'or chained twice', {
    it 'produces three alternates', {
      my @or3 = User.where({fname => 'Alice'})
                    .or(User.where({fname => 'Bob'}))
                    .or(User.where({fname => 'Dave'}))
                    .order('fname').all;

      expect(@or3.elems).to.eq(3);
    }

    it 'returned the right names', {
      my @or3 = User.where({fname => 'Alice'})
                    .or(User.where({fname => 'Bob'}))
                    .or(User.where({fname => 'Dave'}))
                    .order('fname').all;

      expect(@or3.map({ .fname }).join(',')).to.eq('Alice,Bob,Dave');
    }
  }

  context 'or honors negation', {
    it 'returns 3 rows', {
      my @or-not = User.where({fname => 'Alice'}).or(User.where.not({fname => 'Carol'})).order('fname').all;

      expect(@or-not.elems).to.eq(3);
    }

    it 'excludes Carol', {
      my @or-not = User.where({fname => 'Alice'}).or(User.where.not({fname => 'Carol'})).order('fname').all;

      expect((none @or-not.map: { .fname eq 'Carol' }).Bool).to.be-truthy;
    }
  }

  it 'count honors or', {
    expect(User.where({fname => 'Alice'}).or(User.where({fname => 'Bob'})).count).to.eq(2);
  }

  it 'and combines two relations wheres', {
    my @and = User.where({lname => 'Anderson'}).and(User.where({fname => 'Alice'})).all;

    expect(@and.elems == 1 && @and[0].fname eq 'Alice').to.be-truthy;
  }

  it 'and overrides on conflicting key', {
    my @and-conflict = User.where({fname => 'Alice'}).and(User.where({fname => 'Bob'})).all;

    expect(@and-conflict.elems == 1 && @and-conflict[0].fname eq 'Bob').to.be-truthy;
  }
}
