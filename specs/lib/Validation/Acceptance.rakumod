use ORM::ActiveRecord::Model;

unit module Validation::Acceptance;

class Contract is Model is export {
  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 8, max => 64 } }
    self.validate: 'terms', { :acceptance }
  }
}

GLOBAL::<Contract> := Contract;
