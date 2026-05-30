use ORM::ActiveRecord::Model;

unit module Validation::AllowNilBlank;

class Concert is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { :presence, numericality => { gt => 0 }, allow-nil => True }
  }
}

class Recital is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 3 }, allow-blank => True }
  }
}

class Festival is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name', { length => { min => 3 }, allow_blank => True }
  }
}

GLOBAL::<Concert>  := Concert;
GLOBAL::<Recital>  := Recital;
GLOBAL::<Festival> := Festival;
