use ORM::ActiveRecord::Model;

unit module Validation::Rerun;

class RerunPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',  { :presence }
    self.validate: 'score', { numericality => { gt => 0 } }
  }
}

GLOBAL::<RerunPhevent> := RerunPhevent;
