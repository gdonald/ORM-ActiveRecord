use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class MgUser is Model {
  method table-name { 'users' }
}

describe 'merge', {
  before-each {
    MgUser.destroy-all;
    MgUser.create({fname => 'Alice', lname => 'Anderson'});
    MgUser.create({fname => 'Bob',   lname => 'Brown'});
    MgUser.create({fname => 'Carol', lname => 'Anderson'});
    MgUser.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    MgUser.destroy-all;
  }

  context 'merge ANDs disjoint conditions', {
    it 'returns one row', {
      my @both = MgUser.where({lname => 'Anderson'}).merge(MgUser.where({fname => 'Alice'})).all;

      expect(@both.elems).to.eq(1);
    }

    it 'picked Alice', {
      my @both = MgUser.where({lname => 'Anderson'}).merge(MgUser.where({fname => 'Alice'})).all;

      expect(@both[0].fname).to.eq('Alice');
    }
  }

  it 'merge overrides on conflicting where', {
    my @over = MgUser.where({fname => 'Alice'}).merge(MgUser.where({fname => 'Bob'})).all;

    expect(@over.elems == 1 && @over[0].fname eq 'Bob').to.be-truthy;
  }

  context 'merge with not-on-same-col flips condition', {
    it 'returns 3 rows', {
      my @neg = MgUser.where({fname => 'Alice'}).merge(MgUser.where.not({fname => 'Alice'})).all;

      expect(@neg.elems).to.eq(3);
    }

    it 'has no Alice in the merged result', {
      my @neg = MgUser.where({fname => 'Alice'}).merge(MgUser.where.not({fname => 'Alice'})).all;

      expect((none @neg.map: { .fname eq 'Alice' }).Bool).to.be-truthy;
    }
  }

  it 'merge takes other.limit when set', {
    my @l = MgUser.limit(10).merge(MgUser.limit(2)).order('id').all;

    expect(@l.elems).to.eq(2);
  }

  it 'merge appends order: Anderson then by fname picks Alice first', {
    my @o = MgUser.order('lname').merge(MgUser.order('fname')).all;

    expect(@o[0].lname eq 'Anderson' && @o[0].fname eq 'Alice').to.be-truthy;
  }

  it 'merge takes other.offset when set', {
    my @off = MgUser.merge(MgUser.offset(2)).order('id').all;

    expect(@off.elems).to.eq(2);
  }
}
