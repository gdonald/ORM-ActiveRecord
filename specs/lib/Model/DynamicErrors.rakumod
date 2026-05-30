use ORM::ActiveRecord::Model;

unit module Model::DynamicErrors;

class User is Model is export {
  submethod BUILD {
    self.validate: 'fname', { :presence, length => { min => 4 },
      message => '{model} {attribute} needs at least {value} characters' }
  }
}

GLOBAL::<User> := User;
