use ORM::ActiveRecord::Model;

unit module Validation::Exclusion;

class Person is Model is export {
  submethod BUILD {
    self.validate: 'username', { :presence, exclusion => { in => <admin superuser> } }
  }
}

GLOBAL::<Person> := Person;
