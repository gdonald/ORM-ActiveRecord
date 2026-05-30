use ORM::ActiveRecord::Model;

unit module Validation::PresenceOnCreate;

class User is Model is export {
  submethod BUILD {
    self.validate: 'fname', { :presence, on => { :create } }
  }
}

GLOBAL::<User> := User;
