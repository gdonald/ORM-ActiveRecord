use ORM::ActiveRecord::Model;

unit module Validation::UniquenessConditions;

class PhuserActive is Model is export {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { conditions => { is_active => True } } }
  }
}

class PhuserScopeCond is Model is export {
  method table-name { 'phusers' }

  submethod BUILD {
    self.validate: 'username',
      { uniqueness => { scope => :tenant_id, conditions => { is_active => True } } }
  }
}

GLOBAL::<PhuserActive>    := PhuserActive;
GLOBAL::<PhuserScopeCond> := PhuserScopeCond;
