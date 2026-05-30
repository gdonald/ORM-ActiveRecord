use ORM::ActiveRecord::Model;

unit module Validation::Dsl;

class PhMulti is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates: <name>, { :presence, length => { min => 2, max => 8 } }
    self.validates: <score max_score>, { :presence };
  }
}

GLOBAL::<PhMulti> := PhMulti;
