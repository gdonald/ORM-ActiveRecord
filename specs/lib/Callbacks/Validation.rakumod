use ORM::ActiveRecord::Model;

unit module Callbacks::Validation;

our @events is export = ();

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-validation: -> { @events.push: 'before' };
    self.after-validation:  -> { @events.push: 'after'  };
  }
}

GLOBAL::<Client> := Client;
