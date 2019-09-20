
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

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence, :confirmation, length => { min => 5 } }
  }
}

class Person is Model is export {
  submethod BUILD {
    self.validate: 'username', { :presence, :uniqueness, exclusion => { in => <admin superuser> } }
  }
}

class Image is Model is export {
  submethod BUILD {
    self.validate: 'format', { :presence, inclusion => { in => <gif jpeg jpg png> } }
  }
}

class Contact is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence, format => { with => /:i ^<[\w]>+ '@' <[\w]>+ '.' <[\w]>+$/ } }
    self.validate: 'fname', { :presence, length => { is => 7 } }
    self.validate: 'lname', { :presence, length => { in => 4..32 } }
  }
}

class Book is Model is export {
  submethod BUILD {
    self.validate: 'title', { :presence }
    self.validate: 'pages', { :presence, numericality => { lt => 400 } }
    self.validate: 'sentences', { :presence, numericality => { gt => 1000 } }
    self.validate: 'words', { :presence, numericality => { in => 2000..5000 } }
    self.validate: 'periods', { :presence, numericality => { gte => 1000 } }
    self.validate: 'commas', { :presence, numericality => { lte => 200 } }
  }
}
