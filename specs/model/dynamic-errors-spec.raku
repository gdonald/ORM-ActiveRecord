use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class DeUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4 },
      message => '{model} {attribute} needs at least {value} characters' }
  }
}

describe 'dynamic error message interpolation', {
  my $user;

  before-each {
    $user = DeUser.build({fname => 'Foo'});
    $user.is-valid;
  }

  after-each {
    DeUser.destroy-all;
  }

  it 'reports the record as invalid', {
    expect($user.is-valid).to.be-falsy;
  }

  it 'interpolates {model}, {attribute}, and {value}', {
    expect($user.errors.fname[0]).to.match(/'DeUser fname needs at least 4 characters'/);
  }
}
