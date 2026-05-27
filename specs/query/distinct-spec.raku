use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class DiUser is Model {
  method table-name { 'users' }
}

describe 'distinct', {
  before-each {
    DiUser.destroy-all;
    DiUser.create({fname => 'Alice', lname => 'Anderson'});
    DiUser.create({fname => 'Bob',   lname => 'Anderson'});
    DiUser.create({fname => 'Carol', lname => 'Brown'});
    DiUser.create({fname => 'Carol', lname => 'Brown'});
  }

  after-each {
    DiUser.destroy-all;
  }

  it 'has the baseline of 4 rows', {
    expect(DiUser.all.all.elems).to.eq(4);
  }

  it 'distinct over all columns keeps every row', {
    expect(DiUser.distinct.all.elems).to.eq(4);
  }

  context 'distinct + select on a single column', {
    it 'collapses to 2 lnames', {
      my @lnames = DiUser.select('lname').distinct.pluck('lname').sort;

      expect(@lnames.elems).to.eq(2);
    }

    it 'distinct lnames are Anderson and Brown', {
      my @lnames = DiUser.select('lname').distinct.pluck('lname').sort;

      expect(@lnames.join(',')).to.eq('Anderson,Brown');
    }
  }

  it 'distinct(False) re-enables duplicates', {
    my @lnames-all = DiUser.select('lname').distinct.distinct(False).pluck('lname');

    expect(@lnames-all.elems).to.eq(4);
  }

  it 'distinct.count without select == row count', {
    expect(DiUser.distinct.count).to.eq(4);
  }

  it 'distinct count over lname == 2', {
    expect(DiUser.select('lname').distinct.count).to.eq(2);
  }

  it 'distinct count over fname == 3', {
    expect(DiUser.select('fname').distinct.count).to.eq(3);
  }

  it 'unscope(:distinct) clears the flag', {
    expect(DiUser.distinct.unscope(:distinct).distinct-value).to.eq(False);
  }

  it 'merge propagates distinct', {
    expect(DiUser.all.merge(DiUser.distinct).distinct-value).to.eq(True);
  }

  it 'distinct composes with where', {
    my @anders = DiUser.where({lname => 'Anderson'}).select('lname').distinct.pluck('lname');

    expect(@anders.elems == 1 && @anders[0] eq 'Anderson').to.be-truthy;
  }
}
