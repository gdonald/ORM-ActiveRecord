use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class NnUser is Model {
  method table-name { 'users' }
}

describe 'none', {
  before-each {
    NnUser.destroy-all;
    NnUser.create({fname => 'Alice', lname => 'A'});
    NnUser.create({fname => 'Bob',   lname => 'B'});
    NnUser.create({fname => 'Carol', lname => 'C'});
  }

  after-each {
    NnUser.destroy-all;
  }

  it 'Model.none.all returns no rows', {
    expect(NnUser.none.all.elems).to.eq(0);
  }

  it 'Model.none.count is 0', {
    expect(NnUser.none.count).to.eq(0);
  }

  it 'Model.none.exists is False', {
    expect(NnUser.none.exists).to.eq(False);
  }

  it 'Model.none.first is Nil', {
    expect(NnUser.none.first.defined).to.be-falsy;
  }

  it 'Model.none.last is Nil', {
    expect(NnUser.none.last.defined).to.be-falsy;
  }

  it 'none is chainable: where + order still empty', {
    my @chained = NnUser.none.where({fname => 'Alice'}).order('id').all;

    expect(@chained.elems).to.eq(0);
  }

  it 'none.pluck returns empty', {
    my @plucked = NnUser.none.pluck('fname');

    expect(@plucked.elems).to.eq(0);
  }

  it 'none.ids returns empty', {
    my @ids = NnUser.none.ids;

    expect(@ids.elems).to.eq(0);
  }

  it 'merge(other.none) makes the result empty', {
    my @merged = NnUser.where({fname => 'Alice'}).merge(NnUser.none).all;

    expect(@merged.elems).to.eq(0);
  }

  it 'none stays none after further chaining', {
    my @still = NnUser.none.where({fname => 'Bob'}).all;

    expect(@still.elems).to.eq(0);
  }

  it 'control: non-none still queries normally', {
    expect(NnUser.all.count).to.eq(3);
  }
}
