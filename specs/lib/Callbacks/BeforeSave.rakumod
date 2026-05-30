use ORM::ActiveRecord::Model;

unit module Callbacks::BeforeSave;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-save: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

GLOBAL::<Client> := Client;
