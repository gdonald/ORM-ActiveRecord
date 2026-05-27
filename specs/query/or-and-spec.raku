use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class OaUser is Model {
  method table-name { 'users' }
}

describe 'or / and', {
  before-each {
    OaUser.destroy-all;
    OaUser.create({fname => 'Alice', lname => 'Anderson'});
    OaUser.create({fname => 'Bob',   lname => 'Brown'});
    OaUser.create({fname => 'Carol', lname => 'Crane'});
    OaUser.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    OaUser.destroy-all;
  }

  context 'or with two simple wheres', {
    it 'merges two relations into a disjunction', {
      my @or = OaUser.where({fname => 'Alice'}).or(OaUser.where({fname => 'Carol'})).order('fname').all;

      expect(@or.elems).to.eq(2);
    }

    it 'returned both alternates', {
      my @or = OaUser.where({fname => 'Alice'}).or(OaUser.where({fname => 'Carol'})).order('fname').all;

      expect(@or.map({ .fname }).join(',')).to.eq('Alice,Carol');
    }
  }

  context 'or chained twice', {
    it 'produces three alternates', {
      my @or3 = OaUser.where({fname => 'Alice'})
                    .or(OaUser.where({fname => 'Bob'}))
                    .or(OaUser.where({fname => 'Dave'}))
                    .order('fname').all;

      expect(@or3.elems).to.eq(3);
    }

    it 'returned the right names', {
      my @or3 = OaUser.where({fname => 'Alice'})
                    .or(OaUser.where({fname => 'Bob'}))
                    .or(OaUser.where({fname => 'Dave'}))
                    .order('fname').all;

      expect(@or3.map({ .fname }).join(',')).to.eq('Alice,Bob,Dave');
    }
  }

  context 'or honors negation', {
    it 'returns 3 rows', {
      my @or-not = OaUser.where({fname => 'Alice'}).or(OaUser.where.not({fname => 'Carol'})).order('fname').all;

      expect(@or-not.elems).to.eq(3);
    }

    it 'excludes Carol', {
      my @or-not = OaUser.where({fname => 'Alice'}).or(OaUser.where.not({fname => 'Carol'})).order('fname').all;

      expect((none @or-not.map: { .fname eq 'Carol' }).Bool).to.be-truthy;
    }
  }

  it 'count honors or', {
    expect(OaUser.where({fname => 'Alice'}).or(OaUser.where({fname => 'Bob'})).count).to.eq(2);
  }

  it 'and combines two relations wheres', {
    my @and = OaUser.where({lname => 'Anderson'}).and(OaUser.where({fname => 'Alice'})).all;

    expect(@and.elems == 1 && @and[0].fname eq 'Alice').to.be-truthy;
  }

  it 'and overrides on conflicting key', {
    my @and-conflict = OaUser.where({fname => 'Alice'}).and(OaUser.where({fname => 'Bob'})).all;

    expect(@and-conflict.elems == 1 && @and-conflict[0].fname eq 'Bob').to.be-truthy;
  }
}
