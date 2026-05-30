use ORM::ActiveRecord::Model;

unit module Callbacks::BeforeUpdate;

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-update: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

GLOBAL::<Client> := Client;
