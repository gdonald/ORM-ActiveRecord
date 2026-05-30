use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'belongs-to with default foreign-key', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves the parent record', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});

    expect($user.is-valid).to.be-truthy;
  }

  it 'saves the child record', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    my $page = Page.create({user => $user, name => 'Raku'});

    expect($page.is-valid).to.be-truthy;
  }

  it 'fills the foreign-key column on the child', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    my $page = Page.create({user => $user, name => 'Raku'});

    expect($page.user_id).to.eq($user.id);
  }
}
