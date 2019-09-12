
use ORM::ActiveRecord;

class Page {...} # stub

class User is ActiveRecord is export {
  submethod BUILD {
    self.has-many: pages => class => Page;

    self.validate: 'fname', {
      :presence, length => { min => 4, max => 32 }
    }

    self.validate: 'lname', {
      :presence, length => { min => 4, max => 32 }
    }
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class Page is ActiveRecord is export {
  submethod BUILD {
    self.belongs-to: user => class => User;

    self.validate: 'name', {
      :presence, length => { min => 4, max => 32 }
    }
  }
}
