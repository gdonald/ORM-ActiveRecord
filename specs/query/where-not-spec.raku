use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WntUser is Model {
  method table-name { 'users' }
}

describe 'where.not', {
  before-each {
    WntUser.destroy-all;
    WntUser.create({fname => 'Alice', lname => 'Anderson'});
    WntUser.create({fname => 'Bob',   lname => 'Brown'});
    WntUser.create({fname => 'Carol', lname => 'Crane'});
    WntUser.create({fname => 'Dave',  lname => 'Davis'});
  }

  after-each {
    WntUser.destroy-all;
  }

  context 'Model.where.not', {
    it 'excludes one row', {
      my @not-bob = WntUser.where.not({fname => 'Bob'}).order('fname').all;

      expect(@not-bob.elems).to.eq(3);
    }

    it 'returns the rest', {
      my @not-bob = WntUser.where.not({fname => 'Bob'}).order('fname').all;

      expect(@not-bob.map({ .fname }).join(',')).to.eq('Alice,Carol,Dave');
    }
  }

  it 'count honors where.not', {
    expect(WntUser.where.not({fname => 'Bob'}).count).to.eq(3);
  }

  context 'where + not chain narrows correctly', {
    it 'returns one row', {
      my @adults = WntUser.where({lname => 'Anderson'}).not({fname => 'Bob'}).all;

      expect(@adults.elems).to.eq(1);
    }

    it 'picked Alice', {
      my @adults = WntUser.where({lname => 'Anderson'}).not({fname => 'Bob'}).all;

      expect(@adults[0].fname).to.eq('Alice');
    }
  }

  context 'multiple not keys ANDed', {
    it 'returns 2 rows', {
      my @two-out = WntUser.where.not({fname => 'Bob', lname => 'Crane'}).order('fname').all;

      expect(@two-out.elems).to.eq(2);
    }

    it 'excluded both', {
      my @two-out = WntUser.where.not({fname => 'Bob', lname => 'Crane'}).order('fname').all;

      expect(@two-out.map({ .fname }).join(',')).to.eq('Alice,Dave');
    }
  }

  it 'first honors where.not', {
    my $not-alice-first = WntUser.where.not({fname => 'Alice'}).order('fname').first;

    expect($not-alice-first.fname).to.eq('Bob');
  }

  it 'last honors where.not', {
    my $not-dave-last = WntUser.where.not({fname => 'Dave'}).last;

    expect($not-dave-last.fname).to.eq('Carol');
  }

  it 'pluck honors where.not', {
    my @names = WntUser.where.not({fname => 'Bob'}).order('fname').pluck('fname');

    expect(@names.join(',')).to.eq('Alice,Carol,Dave');
  }
}
