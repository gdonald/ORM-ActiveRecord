use ORM::ActiveRecord::Model;

unit module Validation::Context;

class Pageant is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :step_one } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

class Parade is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :create } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

GLOBAL::<Pageant> := Pageant;
GLOBAL::<Parade>  := Parade;
