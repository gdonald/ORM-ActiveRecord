use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Errors::X;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe '-or-die variants', {
  before-each {
    User.destroy-all;
  }

  after-each {
    User.destroy-all;
  }

  context 'create-or-die on the happy path', {
    my $alice;

    before-each {
      $alice = User.create-or-die({fname => 'Alice'});
    }

    it 'returns a persisted record', {
      expect($alice.id).to.be-greater-than(0);
    }

    it 'returns a valid record', {
      expect($alice.is-valid).to.be-truthy;
    }
  }

  context 'create-or-die on the failure path', {
    it 'raises X::RecordInvalid', {
      expect({ User.create-or-die({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }

    it 'carries at least one message on the exception', {
      my $caught;

      try {
        User.create-or-die({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.elems).to.be-greater-than(0);
    }

    it 'references the failing field in the message', {
      my $caught;

      try {
        User.create-or-die({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.first.contains('fname')).to.be-truthy;
    }
  }

  context 'save-or-die on the happy path', {
    it 'returns self', {
      my $alice = User.create-or-die({fname => 'Alice'});

      expect($alice.save-or-die).to.eq($alice);
    }
  }

  context 'update-or-die on the failure path', {
    it 'raises X::RecordInvalid', {
      my $alice = User.create-or-die({fname => 'Alice'});

      expect({ $alice.update-or-die({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }
  }

  context 'update-or-die on the happy path', {
    it 'persists the change', {
      my $bob = User.create({fname => 'Bob'});
      $bob.update-or-die({fname => 'Robert'});

      expect(User.where({fname => 'Robert'}).count).to.eq(1);
    }
  }

  context 'failure paths', {
    it 'leak no rows', {
      my $alice = User.create-or-die({fname => 'Alice'});
      try { User.create-or-die({fname => ''}) };

      my $bob = User.create({fname => 'Bob'});
      try { $bob.update-or-die({fname => ''}) };

      expect(User.count).to.eq(2);
    }
  }
}
