use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'readonly', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
  }

  after-each {
    User.destroy-all;
  }

  context 'default', {
    it 'fresh fetch is not readonly', {
      my $user = User.find-by({fname => 'Alice'});

      expect($user.is-readonly).to.be-falsy;
    }

    it 'normal save still works', {
      my $user = User.find-by({fname => 'Alice'});
      $user.fname = 'Alicia';

      expect($user.save).to.be-truthy;
    }
  }

  context 'readonly through the relation', {
    it 'still returns rows', {
      my @users = User.readonly.all;

      expect(@users.elems).to.eq(2);
    }

    it 'flags every record', {
      my @users = User.readonly.all;

      expect(@users.map({ .is-readonly }).all.Bool).to.be-truthy;
    }
  }

  it 'save on readonly record raises X::ReadOnlyRecord', {
    my @users = User.readonly.all;
    my $ro = @users[0];
    $ro.fname = 'Nope';

    expect({ $ro.save }).to.raise-error(X::ReadOnlyRecord);
  }

  it 'delete on readonly record raises X::ReadOnlyRecord', {
    my @users = User.readonly.all;
    my $ro = @users[0];

    expect({ $ro.delete }).to.raise-error(X::ReadOnlyRecord);
  }

  it 'first picks up readonly flag', {
    my $f = User.readonly.first;

    expect($f.is-readonly).to.be-truthy;
  }

  it 'unscope(:readonly) clears the flag', {
    my @writeable = User.readonly.unscope(:readonly).all;

    expect((none @writeable.map: { .is-readonly }).Bool).to.be-truthy;
  }

  it 'merge propagates readonly', {
    expect(User.all.merge(User.readonly).readonly-value).to.eq(True);
  }
}
