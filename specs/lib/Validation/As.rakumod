use ORM::ActiveRecord::Model;

unit module Validation::As;

class Premiere is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'max_score', { :presence, as => 'Maximum Score', message => '{attribute} must be present' }
  }
}

class Encore is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { numericality => { gte => 10 }, as => 'Player Score', message => '{attribute} must be at least {value}' }
  }
}

GLOBAL::<Premiere> := Premiere;
GLOBAL::<Encore>   := Encore;
