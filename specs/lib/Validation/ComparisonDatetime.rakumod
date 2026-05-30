use ORM::ActiveRecord::Model;

unit module Validation::ComparisonDatetime;

class Showtime is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'ends_at', { comparison => { gt => 'starts_at' } }
  }
}

class Curtain is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'starts_at', { comparison => { gte => DateTime.new('2026-01-01T00:00:00Z') } }
  }
}

GLOBAL::<Showtime> := Showtime;
GLOBAL::<Curtain>  := Curtain;
