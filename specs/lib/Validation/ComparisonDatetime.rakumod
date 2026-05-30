use ORM::ActiveRecord::Model;

unit module Validation::ComparisonDatetime;

class Phdt is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'ends_at', { comparison => { gt => 'starts_at' } }
  }
}

class PhdtLit is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'starts_at', { comparison => { gte => DateTime.new('2026-01-01T00:00:00Z') } }
  }
}

GLOBAL::<Phdt>    := Phdt;
GLOBAL::<PhdtLit> := PhdtLit;
