use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class Page {...}

class User is Model {
  submethod BUILD {
    self.has-many: pages => class => Page;

    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class Page is Model {
  submethod BUILD {
    self.belongs-to: user => class => User;

    self.validate: 'name', { :presence, length => { min => 4, max => 32 } }
  }
}

describe 'User', {
  before-each {
    Page.destroy-all;
    User.destroy-all;
  }

  after-each {
    Page.destroy-all;
    User.destroy-all;
  }

  it 'persists fname and lname on create', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    expect($user.id > 0).to.be(True);
    expect($user.fname).to.be('Greg');
    expect($user.lname).to.be('Donald');
  }

  it 'exposes a fullname helper', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    expect($user.fullname).to.be('Greg Donald');
  }

  it 'rejects an empty fname', {
    my $user = User.build({fname => '', lname => 'Donald'});
    expect($user.is-invalid).to.be(True);
  }
}
