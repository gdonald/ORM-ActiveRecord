use ORM::ActiveRecord::Model;

unit module Validation::I18n;

class Recital is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name',      { :presence };
    self.validate: 'name',      { length => { max => 3 } };
    self.validate: 'max_score', { numericality => { gt => 1 } };
  }
}

GLOBAL::<Recital> := Recital;
