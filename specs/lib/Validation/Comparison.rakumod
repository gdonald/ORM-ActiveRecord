use ORM::ActiveRecord::Model;

unit module Validation::Comparison;

class Sonata is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { comparison => { gt => 0 } }
    self.validate: 'max_score', { comparison => { gte => 'score' } }
  }
}

class Anthem is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { comparison => { lt => 100 } }
    self.validate: 'max_score', { comparison => { lte => 100 } }
  }
}

class Ballad is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { comparison => { eq => 'max_score' } }
  }
}

class Rondo is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'score', { comparison => { ne => 'max_score' } }
  }
}

GLOBAL::<Sonata> := Sonata;
GLOBAL::<Anthem> := Anthem;
GLOBAL::<Ballad> := Ballad;
GLOBAL::<Rondo>  := Rondo;
