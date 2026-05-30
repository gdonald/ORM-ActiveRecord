use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'none', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'A'});
    User.create({fname => 'Bob',   lname => 'B'});
    User.create({fname => 'Carol', lname => 'C'});
  }

  after-each {
    User.destroy-all;
  }

  it 'Model.none.all returns no rows', {
    expect(User.none.all.elems).to.eq(0);
  }

  it 'Model.none.count is 0', {
    expect(User.none.count).to.eq(0);
  }

  it 'Model.none.exists is False', {
    expect(User.none.exists).to.eq(False);
  }

  it 'Model.none.first is Nil', {
    expect(User.none.first.defined).to.be-falsy;
  }

  it 'Model.none.last is Nil', {
    expect(User.none.last.defined).to.be-falsy;
  }

  it 'none is chainable: where + order still empty', {
    my @chained = User.none.where({fname => 'Alice'}).order('id').all;

    expect(@chained.elems).to.eq(0);
  }

  it 'none.pluck returns empty', {
    my @plucked = User.none.pluck('fname');

    expect(@plucked.elems).to.eq(0);
  }

  it 'none.ids returns empty', {
    my @ids = User.none.ids;

    expect(@ids.elems).to.eq(0);
  }

  it 'merge(other.none) makes the result empty', {
    my @merged = User.where({fname => 'Alice'}).merge(User.none).all;

    expect(@merged.elems).to.eq(0);
  }

  it 'none stays none after further chaining', {
    my @still = User.none.where({fname => 'Bob'}).all;

    expect(@still.elems).to.eq(0);
  }

  it 'control: non-none still queries normally', {
    expect(User.all.count).to.eq(3);
  }
}
