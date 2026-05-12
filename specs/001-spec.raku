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

  it 'reports relation predicates', {
    expect(User.is-empty).to.be(True);
    User.create({fname => 'Greg', lname => 'Donald'});
    expect(User.is-any).to.be(True);
    expect(User.is-one).to.be(True);
    expect(User.is-many).to.be(False);
  }

  it 'is-none tracks the explicit .none scope, not the row count', {
    expect(User.where({fname => 'Nobody'}).is-none).to.be(False);
    expect(User.none.is-none).to.be(True);
  }

  it 'cache-key namespaces by table and SQL fingerprint', {
    User.create({fname => 'Greg', lname => 'Donald'});
    my $key = User.cache-key;
    expect($key.starts-with('users/query-')).to.be(True);
    expect(User.cache-key).to.be(User.all.cache-key);
    expect(User.cache-key).not.to.be(User.where({fname => 'Greg'}).cache-key);
  }

  it 'cache-version starts at 0 and flips on insert', {
    expect(User.cache-version).to.be('0');
    User.create({fname => 'Greg', lname => 'Donald'});
    expect(User.cache-version).not.to.be('0');
  }

  it 'explain returns a non-empty plan', {
    User.create({fname => 'Greg', lname => 'Donald'});
    my $plan = User.where({fname => 'Greg'}).explain;
    expect($plan.defined && $plan.chars > 0).to.be(True);
  }
}
