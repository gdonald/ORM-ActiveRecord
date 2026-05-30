use ORM::ActiveRecord::Model;

unit module Validation::Uniqueness;

class Person is Model is export {
  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

GLOBAL::<Person> := Person;
