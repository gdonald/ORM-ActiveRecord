use ORM::ActiveRecord::Model;

unit module Validation::ContactLength;

class Contact is Model is export {
  submethod BUILD {
    self.validate: 'fname', { length => { is => 7 } }
    self.validate: 'lname', { length => { in => 4..32 } }
  }
}

GLOBAL::<Contact> := Contact;
