use ORM::ActiveRecord::Model;

unit module Validation::Dsl;

class Carnival is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates: <name>, { :presence, length => { min => 2, max => 8 } }
    self.validates: <score max_score>, { :presence };
  }
}

GLOBAL::<Carnival> := Carnival;
