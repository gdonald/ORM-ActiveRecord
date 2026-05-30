use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'update and save', {
  after-each {
    User.destroy-all;
  }

  it 'is valid after create with a present fname', {
    my $user = User.create({fname => 'Fred'});

    expect($user.is-valid).to.be-truthy;
  }

  it 'saves after mutating an attribute', {
    my $user = User.create({fname => 'Fred'});
    $user.fname = 'John';

    expect($user.save).to.be-truthy;
  }

  it 'reflects the new value on the in-memory record', {
    my $user = User.create({fname => 'Fred'});
    $user.fname = 'John';
    $user.save;

    expect($user.fname).to.eq('John');
  }
}
