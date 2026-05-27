use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class DsArticle is Model {
  method table-name { 'articles' }
}

class DsUser is Model {
  method table-name { 'users' }

  has Int $.before-count is rw = 0;
  has Int $.after-count  is rw = 0;

  submethod BUILD {
    self.before-destroy: -> { self.before-count++ };
    self.after-destroy:  -> { self.after-count++  };
  }
}

describe 'destroy', {
  before-each {
    DsUser.destroy-all;
    DsArticle.destroy-all;
  }

  after-each {
    DsUser.destroy-all;
    DsArticle.destroy-all;
  }

  context 'on an unsaved record', {
    it 'returns False', {
      my $unsaved = DsUser.new(:id(0));

      expect($unsaved.destroy).to.eq(False);
    }

    it 'does not run before-destroy', {
      my $unsaved = DsUser.new(:id(0));
      $unsaved.destroy;

      expect($unsaved.before-count).to.eq(0);
    }
  }

  context 'on a saved record', {
    my $alice;

    before-each {
      $alice = DsUser.create({fname => 'Alice', lname => 'Anderson'});
      DsUser.create({fname => 'Bob', lname => 'Brown'});
    }

    it 'sees two rows before destroy', {
      expect(DsUser.count).to.eq(2);
    }

    it 'returns True on success', {
      expect($alice.destroy).to.be-truthy;
    }

    it 'runs before-destroy exactly once', {
      $alice.destroy;

      expect($alice.before-count).to.eq(1);
    }

    it 'runs after-destroy exactly once', {
      $alice.destroy;

      expect($alice.after-count).to.eq(1);
    }

    it 'clears the id after destroy', {
      $alice.destroy;

      expect($alice.id).to.eq(0);
    }

    it 'removes the row from the table', {
      $alice.destroy;

      expect(DsUser.count).to.eq(1);
    }
  }

  context 'delete (no callbacks)', {
    it 'does not run before-destroy', {
      my $bob = DsUser.create({fname => 'Bob', lname => 'Brown'});

      $bob.delete;

      expect($bob.before-count).to.eq(0);
    }
  }
}
