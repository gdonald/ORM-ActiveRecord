use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class SoUser is Model {
  method table-name { 'users' }
}

describe 'sole', {
  my $alice;

  before-each {
    SoUser.destroy-all;
    $alice = SoUser.create({fname => 'Alice', lname => 'A'});
    SoUser.create({fname => 'Bob',   lname => 'B'});
    SoUser.create({fname => 'Carol', lname => 'A'});
  }

  after-each {
    SoUser.destroy-all;
  }

  it 'returns the one matching row', {
    my $sole = SoUser.where({fname => 'Alice'}).sole;

    expect($sole.defined && $sole.id == $alice.id).to.be-truthy;
  }

  it 'find-sole-by returns the single row', {
    my $by = SoUser.find-sole-by({fname => 'Bob'});

    expect($by.defined && $by.fname eq 'Bob').to.be-truthy;
  }

  context 'sole raises SoleRecordExceeded for >1 match', {
    it 'raises the exception', {
      expect({ SoUser.where({lname => 'A'}).sole }).to.raise-error(X::SoleRecordExceeded);
    }

    it 'message mentions one', {
      my $multi-err;
      try {
        SoUser.where({lname => 'A'}).sole;
        CATCH { when X::SoleRecordExceeded() { $multi-err = $_ } }
      }

      expect($multi-err.message).to.match(/'one'/);
    }
  }

  it 'sole raises RecordNotFound when no match', {
    expect({ SoUser.where({fname => 'Zelda'}).sole }).to.raise-error(X::RecordNotFound);
  }

  it 'find-sole-by raises SoleRecordExceeded for >1', {
    expect({ SoUser.find-sole-by({lname => 'A'}) }).to.raise-error(X::SoleRecordExceeded);
  }

  it 'find-sole-by raises RecordNotFound on miss', {
    expect({ SoUser.find-sole-by({fname => 'Nobody'}) }).to.raise-error(X::RecordNotFound);
  }

  it 'sole on .none raises RecordNotFound', {
    expect({ SoUser.none.sole }).to.raise-error(X::RecordNotFound);
  }
}
