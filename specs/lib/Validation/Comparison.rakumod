use ORM::ActiveRecord::Model;

unit module Validation::Comparison;

class Phevent is Model is export {
  submethod BUILD {
    self.validate: 'score', { comparison => { gt => 0 } }
    self.validate: 'max_score', { comparison => { gte => 'score' } }
  }
}

class PhCmp is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { lt => 100 } }
    self.validate: 'max_score', { comparison => { lte => 100 } }
  }
}

class PhEq is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { eq => 'max_score' } }
  }
}

class PhNe is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { ne => 'max_score' } }
  }
}

GLOBAL::<Phevent> := Phevent;
GLOBAL::<PhCmp>   := PhCmp;
GLOBAL::<PhEq>    := PhEq;
GLOBAL::<PhNe>    := PhNe;
