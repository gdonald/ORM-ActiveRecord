use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'merge', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Anderson'});
    User.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    User.destroy-all;
  }

  context 'merge ANDs disjoint conditions', {
    it 'returns one row', {
      my @both = User.where({lname => 'Anderson'}).merge(User.where({fname => 'Alice'})).all;

      expect(@both.elems).to.eq(1);
    }

    it 'picked Alice', {
      my @both = User.where({lname => 'Anderson'}).merge(User.where({fname => 'Alice'})).all;

      expect(@both[0].fname).to.eq('Alice');
    }
  }

  it 'merge overrides on conflicting where', {
    my @over = User.where({fname => 'Alice'}).merge(User.where({fname => 'Bob'})).all;

    expect(@over.elems == 1 && @over[0].fname eq 'Bob').to.be-truthy;
  }

  context 'merge with not-on-same-col flips condition', {
    it 'returns 3 rows', {
      my @neg = User.where({fname => 'Alice'}).merge(User.where.not({fname => 'Alice'})).all;

      expect(@neg.elems).to.eq(3);
    }

    it 'has no Alice in the merged result', {
      my @neg = User.where({fname => 'Alice'}).merge(User.where.not({fname => 'Alice'})).all;

      expect((none @neg.map: { .fname eq 'Alice' }).Bool).to.be-truthy;
    }
  }

  it 'merge takes other.limit when set', {
    my @l = User.limit(10).merge(User.limit(2)).order('id').all;

    expect(@l.elems).to.eq(2);
  }

  it 'merge appends order: Anderson then by fname picks Alice first', {
    my @o = User.order('lname').merge(User.order('fname')).all;

    expect(@o[0].lname eq 'Anderson' && @o[0].fname eq 'Alice').to.be-truthy;
  }

  it 'merge takes other.offset when set', {
    my @off = User.merge(User.offset(2)).order('id').all;

    expect(@off.elems).to.eq(2);
  }
}
