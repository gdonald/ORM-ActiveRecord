use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'distinct', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Anderson'});
    User.create({fname => 'Carol', lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Brown'});
  }

  after-each {
    User.destroy-all;
  }

  it 'has the baseline of 4 rows', {
    expect(User.all.all.elems).to.eq(4);
  }

  it 'distinct over all columns keeps every row', {
    expect(User.distinct.all.elems).to.eq(4);
  }

  context 'distinct + select on a single column', {
    it 'collapses to 2 lnames', {
      my @lnames = User.select('lname').distinct.pluck('lname').sort;

      expect(@lnames.elems).to.eq(2);
    }

    it 'distinct lnames are Anderson and Brown', {
      my @lnames = User.select('lname').distinct.pluck('lname').sort;

      expect(@lnames.join(',')).to.eq('Anderson,Brown');
    }
  }

  it 'distinct(False) re-enables duplicates', {
    my @lnames-all = User.select('lname').distinct.distinct(False).pluck('lname');

    expect(@lnames-all.elems).to.eq(4);
  }

  it 'distinct.count without select == row count', {
    expect(User.distinct.count).to.eq(4);
  }

  it 'distinct count over lname == 2', {
    expect(User.select('lname').distinct.count).to.eq(2);
  }

  it 'distinct count over fname == 3', {
    expect(User.select('fname').distinct.count).to.eq(3);
  }

  it 'unscope(:distinct) clears the flag', {
    expect(User.distinct.unscope(:distinct).distinct-value).to.eq(False);
  }

  it 'merge propagates distinct', {
    expect(User.all.merge(User.distinct).distinct-value).to.eq(True);
  }

  it 'distinct composes with where', {
    my @anders = User.where({lname => 'Anderson'}).select('lname').distinct.pluck('lname');

    expect(@anders.elems == 1 && @anders[0] eq 'Anderson').to.be-truthy;
  }
}
