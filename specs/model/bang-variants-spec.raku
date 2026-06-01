use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Errors::X;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe '-bang variants', {
  before-each {
    User.destroy-all;
  }

  after-each {
    User.destroy-all;
  }

  context 'create-bang on the happy path', {
    my $alice;

    before-each {
      $alice = User.create-bang({fname => 'Alice'});
    }

    it 'returns a persisted record', {
      expect($alice.id).to.be-greater-than(0);
    }

    it 'returns a valid record', {
      expect($alice.is-valid).to.be-truthy;
    }
  }

  context 'create-bang on the failure path', {
    it 'raises X::RecordInvalid', {
      expect({ User.create-bang({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }

    it 'carries at least one message on the exception', {
      my $caught;

      try {
        User.create-bang({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.elems).to.be-greater-than(0);
    }

    it 'references the failing field in the message', {
      my $caught;

      try {
        User.create-bang({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.first.contains('fname')).to.be-truthy;
    }
  }

  context 'save-bang on the happy path', {
    it 'returns self', {
      my $alice = User.create-bang({fname => 'Alice'});

      expect($alice.save-bang).to.eq($alice);
    }
  }

  context 'update-bang on the failure path', {
    it 'raises X::RecordInvalid', {
      my $alice = User.create-bang({fname => 'Alice'});

      expect({ $alice.update-bang({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }
  }

  context 'update-bang on the happy path', {
    it 'persists the change', {
      my $bob = User.create({fname => 'Bob'});
      $bob.update-bang({fname => 'Robert'});

      expect(User.where({fname => 'Robert'}).count).to.eq(1);
    }
  }

  context 'failure paths', {
    it 'leak no rows', {
      my $alice = User.create-bang({fname => 'Alice'});
      try { User.create-bang({fname => ''}) };

      my $bob = User.create({fname => 'Bob'});
      try { $bob.update-bang({fname => ''}) };

      expect(User.count).to.eq(2);
    }
  }
}
