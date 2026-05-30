use ORM::ActiveRecord::Model;

unit module Model::CustomErrors;

class User is Model is export {
  submethod BUILD {
    self.validate: 'fname', { :presence, message => 'fname is required' }
  }
}

GLOBAL::<User> := User;
