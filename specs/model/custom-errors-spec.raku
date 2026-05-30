use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Model::CustomErrors;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'custom error messages', {
  my $user;

  before-each {
    $user = User.build;
    $user.is-valid;
  }

  after-each {
    User.destroy-all;
  }

  it 'reports the record as invalid', {
    expect($user.is-valid).to.be-falsy;
  }

  it 'surfaces the custom message verbatim', {
    expect($user.errors.fname[0]).to.eq('fname is required');
  }
}
