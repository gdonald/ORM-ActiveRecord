use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class FkPage {...}

class FkUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: fkpages => %(class => FkPage, foreign-key => 'user_id');
  }
}

class FkPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: fkuser => %(class => FkUser, foreign-key => 'user_id');
  }
}

describe 'belongs-to with default foreign-key', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves the parent record', {
    my $user = FkUser.create({fname => 'Greg', lname => 'Donald'});

    expect($user.is-valid).to.be-truthy;
  }

  it 'saves the child record', {
    my $user = FkUser.create({fname => 'Greg', lname => 'Donald'});
    my $page = FkPage.create({fkuser => $user, name => 'Raku'});

    expect($page.is-valid).to.be-truthy;
  }

  it 'fills the foreign-key column on the child', {
    my $user = FkUser.create({fname => 'Greg', lname => 'Donald'});
    my $page = FkPage.create({fkuser => $user, name => 'Raku'});

    expect($page.user_id).to.eq($user.id);
  }
}
