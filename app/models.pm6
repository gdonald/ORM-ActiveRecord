
use ORM::ActiveRecord::Model;

class Page {...} # stub

class User is Model is export {
  submethod BUILD {
    self.has-many: pages => class => Page;

    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class Page is Model is export {
  submethod BUILD {
    self.belongs-to: user => class => User;

    self.validate: 'name', { :presence, length => { min => 4, max => 32 } }
  }
}

class Contract is Model is export {
  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 8, max => 64 } }
    self.validate: 'terms', { :acceptance }
  }
}
