use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Model::DynamicErrors;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'dynamic error message interpolation', {
  my $user;

  before-each {
    $user = User.build({fname => 'Foo'});
    $user.is-valid;
  }

  after-each {
    User.destroy-all;
  }

  it 'reports the record as invalid', {
    expect($user.is-valid).to.be-falsy;
  }

  it 'interpolates {model}, {attribute}, and {value}', {
    expect($user.errors.fname[0]).to.match(/'User fname needs at least 4 characters'/);
  }
}
