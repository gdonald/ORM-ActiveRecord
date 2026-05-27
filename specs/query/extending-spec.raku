use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class EtUser is Model {
  method table-name { 'users' }
}

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
    EtUser.destroy-all;
    EtUser.create({fname => 'Alice', lname => 'A'});
    EtUser.create({fname => 'Bob',   lname => 'B'});
    EtUser.create({fname => 'Carol', lname => 'C'});
    EtUser.create({fname => 'Dave',  lname => 'D'});
  }

  after-each {
    EtUser.destroy-all;
  }

  context 'page(1)', {
    it 'returns the first 2 rows', {
      my @page1 = EtUser.order('id').extending(Pagination).page(1).all;

      expect(@page1.elems).to.eq(2);
    }

    it 'returns Alice + Bob', {
      my @page1 = EtUser.order('id').extending(Pagination).page(1).all;

      expect(@page1[0].fname eq 'Alice' && @page1[1].fname eq 'Bob').to.be-truthy;
    }
  }

  it 'page(2) returns Carol + Dave', {
    my @page2 = EtUser.order('id').extending(Pagination).page(2).all;

    expect(@page2.map({ .fname }).join(',')).to.eq('Carol,Dave');
  }

  it 'mixed-in NameOnly.names + Pagination.page composes', {
    my @names = EtUser.order('id').extending(Pagination, NameOnly).page(1).names;

    expect(@names.join(',')).to.eq('Alice,Bob');
  }

  it 'baseline query still works', {
    expect(EtUser.all.count).to.eq(4);
  }

  it 'extending requires at least one role', {
    expect({ EtUser.all.extending }).to.raise-error;
  }
}
