use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class RoUser is Model {
  method table-name { 'users' }
}

describe 'readonly', {
  before-each {
    RoUser.destroy-all;
    RoUser.create({fname => 'Alice', lname => 'Anderson'});
    RoUser.create({fname => 'Bob',   lname => 'Brown'});
  }

  after-each {
    RoUser.destroy-all;
  }

  context 'default', {
    it 'fresh fetch is not readonly', {
      my $user = RoUser.find-by({fname => 'Alice'});

      expect($user.is-readonly).to.be-falsy;
    }

    it 'normal save still works', {
      my $user = RoUser.find-by({fname => 'Alice'});
      $user.fname = 'Alicia';

      expect($user.save).to.be-truthy;
    }
  }

  context 'readonly through the relation', {
    it 'still returns rows', {
      my @users = RoUser.readonly.all;

      expect(@users.elems).to.eq(2);
    }

    it 'flags every record', {
      my @users = RoUser.readonly.all;

      expect(@users.map({ .is-readonly }).all.Bool).to.be-truthy;
    }
  }

  it 'save on readonly record raises X::ReadOnlyRecord', {
    my @users = RoUser.readonly.all;
    my $ro = @users[0];
    $ro.fname = 'Nope';

    expect({ $ro.save }).to.raise-error(X::ReadOnlyRecord);
  }

  it 'delete on readonly record raises X::ReadOnlyRecord', {
    my @users = RoUser.readonly.all;
    my $ro = @users[0];

    expect({ $ro.delete }).to.raise-error(X::ReadOnlyRecord);
  }

  it 'first picks up readonly flag', {
    my $f = RoUser.readonly.first;

    expect($f.is-readonly).to.be-truthy;
  }

  it 'unscope(:readonly) clears the flag', {
    my @writeable = RoUser.readonly.unscope(:readonly).all;

    expect((none @writeable.map: { .is-readonly }).Bool).to.be-truthy;
  }

  it 'merge propagates readonly', {
    expect(RoUser.all.merge(RoUser.readonly).readonly-value).to.eq(True);
  }
}
