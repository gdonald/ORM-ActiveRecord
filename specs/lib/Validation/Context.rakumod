use ORM::ActiveRecord::Model;

unit module Validation::Context;

class CtxPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :step_one } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

class CtxPhevent2 is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :create } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

GLOBAL::<CtxPhevent>  := CtxPhevent;
GLOBAL::<CtxPhevent2> := CtxPhevent2;
