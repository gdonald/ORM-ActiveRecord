use ORM::ActiveRecord::Model;

unit module Validation::PresenceOnUpdate;

class Game is Model is export {
  submethod BUILD {
    self.validate: 'name', { :presence, on => { :update } }
    self.validate: 'year', { :presence, :numericality }
  }
}

GLOBAL::<Game> := Game;
