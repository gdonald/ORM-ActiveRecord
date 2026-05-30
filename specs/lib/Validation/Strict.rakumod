use ORM::ActiveRecord::Model;

unit module Validation::Strict;

class StPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { :presence, strict => True }
  }
}

class StPhevent2 is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { numericality => { gt => 5 }, :strict, message => 'is too low' }
  }
}

GLOBAL::<StPhevent>  := StPhevent;
GLOBAL::<StPhevent2> := StPhevent2;
