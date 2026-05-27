use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CeUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence, message => 'fname is required' }
  }
}

describe 'custom error messages', {
  my $user;

  before-each {
    $user = CeUser.build;
    $user.is-valid;
  }

  after-each {
    CeUser.destroy-all;
  }

  it 'reports the record as invalid', {
    expect($user.is-valid).to.be-falsy;
  }

  it 'surfaces the custom message verbatim', {
    expect($user.errors.fname[0]).to.eq('fname is required');
  }
}
