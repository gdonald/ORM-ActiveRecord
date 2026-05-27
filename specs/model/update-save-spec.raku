use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class UsUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

describe 'update and save', {
  after-each {
    UsUser.destroy-all;
  }

  it 'is valid after create with a present fname', {
    my $user = UsUser.create({fname => 'Fred'});

    expect($user.is-valid).to.be-truthy;
  }

  it 'saves after mutating an attribute', {
    my $user = UsUser.create({fname => 'Fred'});
    $user.fname = 'John';

    expect($user.save).to.be-truthy;
  }

  it 'reflects the new value on the in-memory record', {
    my $user = UsUser.create({fname => 'Fred'});
    $user.fname = 'John';
    $user.save;

    expect($user.fname).to.eq('John');
  }
}
