use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class BvUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence };
  }
}

describe '-or-die variants', {
  before-each {
    BvUser.destroy-all;
  }

  after-each {
    BvUser.destroy-all;
  }

  context 'create-or-die on the happy path', {
    my $alice;

    before-each {
      $alice = BvUser.create-or-die({fname => 'Alice'});
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
      expect({ BvUser.create-or-die({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }

    it 'carries at least one message on the exception', {
      my $caught;

      try {
        BvUser.create-or-die({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.elems).to.be-greater-than(0);
    }

    it 'references the failing field in the message', {
      my $caught;

      try {
        BvUser.create-or-die({fname => ''});
        CATCH { when X::RecordInvalid() { $caught = $_ } }
      }

      expect($caught.messages.first.contains('fname')).to.be-truthy;
    }
  }

  context 'save-or-die on the happy path', {
    it 'returns self', {
      my $alice = BvUser.create-or-die({fname => 'Alice'});

      expect($alice.save-or-die).to.eq($alice);
    }
  }

  context 'update-or-die on the failure path', {
    it 'raises X::RecordInvalid', {
      my $alice = BvUser.create-or-die({fname => 'Alice'});

      expect({ $alice.update-or-die({fname => ''}) }).to.raise-error(X::RecordInvalid);
    }
  }

  context 'update-or-die on the happy path', {
    it 'persists the change', {
      my $bob = BvUser.create({fname => 'Bob'});
      $bob.update-or-die({fname => 'Robert'});

      expect(BvUser.where({fname => 'Robert'}).count).to.eq(1);
    }
  }

  context 'failure paths', {
    it 'leak no rows', {
      my $alice = BvUser.create-or-die({fname => 'Alice'});
      try { BvUser.create-or-die({fname => ''}) };

      my $bob = BvUser.create({fname => 'Bob'});
      try { $bob.update-or-die({fname => ''}) };

      expect(BvUser.count).to.eq(2);
    }
  }
}
