use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'finders', {
  my ($alice, $bob, $carol);

  before-each {
    User.destroy-all;
    $alice = User.create({fname => 'Alice', lname => 'Anderson'});
    $bob   = User.create({fname => 'Bob',   lname => 'Brown'});
    $carol = User.create({fname => 'Carol', lname => 'Crane'});
  }

  after-each {
    User.destroy-all;
  }

  context 'find by id', {
    it 'returns the matching record', {
      my $found = User.find($bob.id);

      expect($found.id).to.eq($bob.id);
    }

    it 'populates attributes', {
      my $found = User.find($bob.id);

      expect($found.fname).to.eq('Bob');
    }
  }

  context 'find raises on miss', {
    it 'raises X::RecordNotFound', {
      expect({ User.find(999_999) }).to.raise-error(X::RecordNotFound);
    }

    it 'carries the id on the exception', {
      my $caught;
      try {
        User.find(999_999);
        CATCH { when X::RecordNotFound() { $caught = $_ } }
      }

      expect($caught.id).to.eq(999_999);
    }

    it 'carries the model name on the exception', {
      my $caught;
      try {
        User.find(999_999);
        CATCH { when X::RecordNotFound() { $caught = $_ } }
      }

      expect($caught.model).to.match(/'User'/);
    }
  }

  it 'find-by returns first match', {
    my $by-fname = User.find-by({fname => 'Carol'});

    expect($by-fname.id).to.eq($carol.id);
  }

  it 'find-by returns Nil on miss', {
    expect(User.find-by({fname => 'Nobody'}).defined).to.be-falsy;
  }

  it 'find-by-or-die raises X::RecordNotFound', {
    expect({ User.find-by-or-die({fname => 'Nobody'}) }).to.raise-error(X::RecordNotFound);
  }

  it 'last returns highest-id record', {
    expect(User.last.id).to.eq($carol.id);
  }

  it 'take(2) returns two records', {
    expect(User.take(2).elems).to.eq(2);
  }

  it 'take defaults to one record', {
    expect(User.take.elems).to.eq(1);
  }

  context 'exists', {
    it 'is True when rows present (no args)', {
      expect(User.exists).to.be-truthy;
    }

    it 'matches with conditions', {
      expect(User.exists({fname => 'Alice'})).to.be-truthy;
    }

    it 'returns False when no match', {
      expect(User.exists({fname => 'Nobody'})).to.be-falsy;
    }
  }
}
