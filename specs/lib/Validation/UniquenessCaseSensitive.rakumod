use ORM::ActiveRecord::Model;

unit module Validation::UniquenessCaseSensitive;

class Patron is Model is export {
  method table-name { 'members' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => False } }
  }
}

class Subscriber is Model is export {
  method table-name { 'members' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => True } }
  }
}

class Visitor is Model is export {
  method table-name { 'members' }

  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

GLOBAL::<Patron>     := Patron;
GLOBAL::<Subscriber> := Subscriber;
GLOBAL::<Visitor>    := Visitor;
