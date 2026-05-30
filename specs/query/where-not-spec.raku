use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'where.not', {
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

  context 'Model.where.not', {
    it 'excludes one row', {
      my @not-bob = User.where.not({fname => 'Bob'}).order('fname').all;

      expect(@not-bob.elems).to.eq(3);
    }

    it 'returns the rest', {
      my @not-bob = User.where.not({fname => 'Bob'}).order('fname').all;

      expect(@not-bob.map({ .fname }).join(',')).to.eq('Alice,Carol,Dave');
    }
  }

  it 'count honors where.not', {
    expect(User.where.not({fname => 'Bob'}).count).to.eq(3);
  }

  context 'where + not chain narrows correctly', {
    it 'returns one row', {
      my @adults = User.where({lname => 'Anderson'}).not({fname => 'Bob'}).all;

      expect(@adults.elems).to.eq(1);
    }

    it 'picked Alice', {
      my @adults = User.where({lname => 'Anderson'}).not({fname => 'Bob'}).all;

      expect(@adults[0].fname).to.eq('Alice');
    }
  }

  context 'multiple not keys ANDed', {
    it 'returns 2 rows', {
      my @two-out = User.where.not({fname => 'Bob', lname => 'Crane'}).order('fname').all;

      expect(@two-out.elems).to.eq(2);
    }

    it 'excluded both', {
      my @two-out = User.where.not({fname => 'Bob', lname => 'Crane'}).order('fname').all;

      expect(@two-out.map({ .fname }).join(',')).to.eq('Alice,Dave');
    }
  }

  it 'first honors where.not', {
    my $not-alice-first = User.where.not({fname => 'Alice'}).order('fname').first;

    expect($not-alice-first.fname).to.eq('Bob');
  }

  it 'last honors where.not', {
    my $not-dave-last = User.where.not({fname => 'Dave'}).last;

    expect($not-dave-last.fname).to.eq('Carol');
  }

  it 'pluck honors where.not', {
    my @names = User.where.not({fname => 'Bob'}).order('fname').pluck('fname');

    expect(@names.join(',')).to.eq('Alice,Carol,Dave');
  }
}
