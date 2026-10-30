use ORM::ActiveRecord::Model;

unit module Validation::ZeroNumericality;

class Meter is Model is export {
  submethod BUILD {
    self.validate: 'above_zero',    { numericality => { gt => 0 } }
    self.validate: 'at_least_zero', { numericality => { gte => 0 } }
    self.validate: 'below_zero',    { numericality => { lt => 0 } }
    self.validate: 'at_most_zero',  { numericality => { lte => 0 } }
    self.validate: 'balance',       { numericality => { gte => 0 } }
  }
}

GLOBAL::<Meter> := Meter;
