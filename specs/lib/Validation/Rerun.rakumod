use ORM::ActiveRecord::Model;

unit module Validation::Rerun;

class Replay is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name',  { :presence }
    self.validate: 'score', { numericality => { gt => 0 } }
  }
}

GLOBAL::<Replay> := Replay;
