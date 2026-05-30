use ORM::ActiveRecord::Model;

unit module Validation::UniquenessCaseSensitive;

class PhuserCI is Model is export {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => False } }
  }
}

class PhuserCS is Model is export {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { case-sensitive => True } }
  }
}

class PhuserDefault is Model is export {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { :uniqueness }
  }
}

GLOBAL::<PhuserCI>      := PhuserCI;
GLOBAL::<PhuserCS>      := PhuserCS;
GLOBAL::<PhuserDefault> := PhuserDefault;
