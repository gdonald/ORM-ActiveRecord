use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class FdUser is Model {
  method table-name { 'users' }
}

describe 'finders', {
  my ($alice, $bob, $carol);

  before-each {
    FdUser.destroy-all;
    $alice = FdUser.create({fname => 'Alice', lname => 'Anderson'});
    $bob   = FdUser.create({fname => 'Bob',   lname => 'Brown'});
    $carol = FdUser.create({fname => 'Carol', lname => 'Crane'});
  }

  after-each {
    FdUser.destroy-all;
  }

  context 'find by id', {
    it 'returns the matching record', {
      my $found = FdUser.find($bob.id);

      expect($found.id).to.eq($bob.id);
    }

    it 'populates attributes', {
      my $found = FdUser.find($bob.id);

      expect($found.fname).to.eq('Bob');
    }
  }

  context 'find raises on miss', {
    it 'raises X::RecordNotFound', {
      expect({ FdUser.find(999_999) }).to.raise-error(X::RecordNotFound);
    }

    it 'carries the id on the exception', {
      my $caught;
      try {
        FdUser.find(999_999);
        CATCH { when X::RecordNotFound() { $caught = $_ } }
      }

      expect($caught.id).to.eq(999_999);
    }

    it 'carries the model name on the exception', {
      my $caught;
      try {
        FdUser.find(999_999);
        CATCH { when X::RecordNotFound() { $caught = $_ } }
      }

      expect($caught.model).to.match(/'FdUser'/);
    }
  }

  it 'find-by returns first match', {
    my $by-fname = FdUser.find-by({fname => 'Carol'});

    expect($by-fname.id).to.eq($carol.id);
  }

  it 'find-by returns Nil on miss', {
    expect(FdUser.find-by({fname => 'Nobody'}).defined).to.be-falsy;
  }

  it 'find-by-or-die raises X::RecordNotFound', {
    expect({ FdUser.find-by-or-die({fname => 'Nobody'}) }).to.raise-error(X::RecordNotFound);
  }

  it 'last returns highest-id record', {
    expect(FdUser.last.id).to.eq($carol.id);
  }

  it 'take(2) returns two records', {
    expect(FdUser.take(2).elems).to.eq(2);
  }

  it 'take defaults to one record', {
    expect(FdUser.take.elems).to.eq(1);
  }

  context 'exists', {
    it 'is True when rows present (no args)', {
      expect(FdUser.exists).to.be-truthy;
    }

    it 'matches with conditions', {
      expect(FdUser.exists({fname => 'Alice'})).to.be-truthy;
    }

    it 'returns False when no match', {
      expect(FdUser.exists({fname => 'Nobody'})).to.be-falsy;
    }
  }
}
