use ORM::ActiveRecord::Model;

unit module Validation::Confirmation;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence, :confirmation }
  }
}

GLOBAL::<Client> := Client;
