use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'sole', {
  my $alice;

  before-each {
    User.destroy-all;
    $alice = User.create({fname => 'Alice', lname => 'A'});
    User.create({fname => 'Bob',   lname => 'B'});
    User.create({fname => 'Carol', lname => 'A'});
  }

  after-each {
    User.destroy-all;
  }

  it 'returns the one matching row', {
    my $sole = User.where({fname => 'Alice'}).sole;

    expect($sole.defined && $sole.id == $alice.id).to.be-truthy;
  }

  it 'find-sole-by returns the single row', {
    my $by = User.find-sole-by({fname => 'Bob'});

    expect($by.defined && $by.fname eq 'Bob').to.be-truthy;
  }

  context 'sole raises SoleRecordExceeded for >1 match', {
    it 'raises the exception', {
      expect({ User.where({lname => 'A'}).sole }).to.raise-error(X::SoleRecordExceeded);
    }

    it 'message mentions one', {
      my $multi-err;
      try {
        User.where({lname => 'A'}).sole;
        CATCH { when X::SoleRecordExceeded() { $multi-err = $_ } }
      }

      expect($multi-err.message).to.match(/'one'/);
    }
  }

  it 'sole raises RecordNotFound when no match', {
    expect({ User.where({fname => 'Zelda'}).sole }).to.raise-error(X::RecordNotFound);
  }

  it 'find-sole-by raises SoleRecordExceeded for >1', {
    expect({ User.find-sole-by({lname => 'A'}) }).to.raise-error(X::SoleRecordExceeded);
  }

  it 'find-sole-by raises RecordNotFound on miss', {
    expect({ User.find-sole-by({fname => 'Nobody'}) }).to.raise-error(X::RecordNotFound);
  }

  it 'sole on .none raises RecordNotFound', {
    expect({ User.none.sole }).to.raise-error(X::RecordNotFound);
  }
}
