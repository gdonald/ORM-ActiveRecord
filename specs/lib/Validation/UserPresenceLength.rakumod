use ORM::ActiveRecord::Model;

unit module Validation::UserPresenceLength;

class User is Model is export {
  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }
}

GLOBAL::<User> := User;
