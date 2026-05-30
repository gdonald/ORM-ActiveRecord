use ORM::ActiveRecord::Model;

unit module Validation::AllowNilBlank;

class AnbPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { :presence, numericality => { gt => 0 }, allow-nil => True }
  }
}

class AnbPhevent2 is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 3 }, allow-blank => True }
  }
}

class AnbPhevent3 is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { length => { min => 3 }, allow_blank => True }
  }
}

GLOBAL::<AnbPhevent> := AnbPhevent;
GLOBAL::<AnbPhevent2> := AnbPhevent2;
GLOBAL::<AnbPhevent3> := AnbPhevent3;
