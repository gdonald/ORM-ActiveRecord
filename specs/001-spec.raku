use BDD::Behave;
use ORM::ActiveRecord::Model;

# Someday, when EVAL is actually useful :(
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

describe -> 'User' {
  let(:user) => { Behavior::User.create({fname => 'Greg', lname => 'Donald'}) };

  it -> 'is persisted' {
    expect(:user.fname).to.eq('Greg');
  }
}
