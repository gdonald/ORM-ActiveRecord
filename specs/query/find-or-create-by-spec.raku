use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class FcUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
  }
}

describe 'find-or-create-by', {
  before-each {
    FcUser.destroy-all;
    FcUser.create({fname => 'Alice', lname => 'A'});
  }

  after-each {
    FcUser.destroy-all;
  }

  context 'returns existing record when found', {
    it 'returns the existing row', {
      my $found = FcUser.find-or-create-by({fname => 'Alice'});

      expect($found.defined && $found.fname eq 'Alice').to.be-truthy;
    }

    it 'does not create a duplicate row', {
      FcUser.find-or-create-by({fname => 'Alice'});

      expect(FcUser.where({fname => 'Alice'}).count).to.eq(1);
    }
  }

  context 'creates a new record when missing', {
    it 'returns a record with an id', {
      my $created = FcUser.find-or-create-by({fname => 'Bobby', lname => 'B'});

      expect($created.defined && $created.id > 0).to.be-truthy;
    }

    it 'makes the new row visible', {
      FcUser.find-or-create-by({fname => 'Bobby', lname => 'B'});

      expect(FcUser.where({fname => 'Bobby'}).count).to.eq(1);
    }
  }

  context 'when validation fails', {
    it 'returns an unsaved invalid record', {
      my $invalid = FcUser.find-or-create-by({fname => 'no'});

      expect($invalid.defined).to.be-truthy;
    }

    it 'does not persist the invalid record', {
      my $invalid = FcUser.find-or-create-by({fname => 'no'});

      expect($invalid.id).to.eq(0);
    }

    it 'returned record has validation errors', {
      my $invalid = FcUser.find-or-create-by({fname => 'no'});

      expect($invalid.is-invalid).to.be-truthy;
    }
  }

  it 'find-or-create-by-or-die raises X::RecordInvalid', {
    expect({ FcUser.find-or-create-by-or-die({fname => 'no'}) }).to.raise-error(X::RecordInvalid);
  }

  context 'scoped on relation', {
    it 'creates a row', {
      my $scoped = FcUser.where({lname => 'Z'}).find-or-create-by({fname => 'Carol'});

      expect($scoped.defined && $scoped.id > 0).to.be-truthy;
    }

    it 'merges where conditions into create attrs', {
      my $scoped = FcUser.where({lname => 'Z'}).find-or-create-by({fname => 'Carol'});

      expect($scoped.lname).to.eq('Z');
    }

    it 'find params win on create attrs', {
      my $scoped = FcUser.where({lname => 'Z'}).find-or-create-by({fname => 'Carol'});

      expect($scoped.fname).to.eq('Carol');
    }

    it 'second call finds the previously-created scoped row', {
      my $scoped = FcUser.where({lname => 'Z'}).find-or-create-by({fname => 'Carol'});

      expect(FcUser.where({lname => 'Z'}).find-or-create-by({fname => 'Carol'}).id).to.eq($scoped.id);
    }
  }

  it 'create-with sets defaults that find params override but lname comes from create-with', {
    my $cw = FcUser.where({lname => 'X'}).create-with({fname => 'DefaultName', lname => 'Override'})
                .find-or-create-by({fname => 'Real-Name'});

    expect($cw.defined && $cw.fname eq 'Real-Name' && $cw.lname eq 'Override').to.be-truthy;
  }
}
