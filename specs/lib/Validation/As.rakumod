use ORM::ActiveRecord::Model;

unit module Validation::As;

class AsPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'max_score', { :presence, as => 'Maximum Score', message => '{attribute} must be present' }
  }
}

class AsPhevent2 is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { numericality => { gte => 10 }, as => 'Player Score', message => '{attribute} must be at least {value}' }
  }
}

GLOBAL::<AsPhevent> := AsPhevent;
GLOBAL::<AsPhevent2> := AsPhevent2;
