use ORM::ActiveRecord::Model;

unit module Validation::Strict;

class Spectacle is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name', { :presence, strict => True }
  }
}

class Gala is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { numericality => { gt => 5 }, :strict, message => 'is too low' }
  }
}

GLOBAL::<Spectacle> := Spectacle;
GLOBAL::<Gala>      := Gala;
