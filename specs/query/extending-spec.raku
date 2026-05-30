use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


role Pagination {
  method page(Int:D $n, Int:D :$per = 2) {
    self.limit($per).offset(($n - 1) * $per);
  }
}

role NameOnly {
  method names {
    self.pluck('fname');
  }
}

describe 'extending', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'A'});
    User.create({fname => 'Bob',   lname => 'B'});
    User.create({fname => 'Carol', lname => 'C'});
    User.create({fname => 'Dave',  lname => 'D'});
  }

  after-each {
    User.destroy-all;
  }

  context 'page(1)', {
    it 'returns the first 2 rows', {
      my @page1 = User.order('id').extending(Pagination).page(1).all;

      expect(@page1.elems).to.eq(2);
    }

    it 'returns Alice + Bob', {
      my @page1 = User.order('id').extending(Pagination).page(1).all;

      expect(@page1[0].fname eq 'Alice' && @page1[1].fname eq 'Bob').to.be-truthy;
    }
  }

  it 'page(2) returns Carol + Dave', {
    my @page2 = User.order('id').extending(Pagination).page(2).all;

    expect(@page2.map({ .fname }).join(',')).to.eq('Carol,Dave');
  }

  it 'mixed-in NameOnly.names + Pagination.page composes', {
    my @names = User.order('id').extending(Pagination, NameOnly).page(1).names;

    expect(@names.join(',')).to.eq('Alice,Bob');
  }

  it 'baseline query still works', {
    expect(User.all.count).to.eq(4);
  }

  it 'extending requires at least one role', {
    expect({ User.all.extending }).to.raise-error;
  }
}
