use ORM::ActiveRecord::Model;

unit module Validation::UniquenessConditions;

class Voter is Model is export {
  method table-name { 'members' }

  submethod BUILD {
    self.validate: 'username', { uniqueness => { conditions => { is_active => True } } }
  }
}

class Donor is Model is export {
  method table-name { 'members' }

  submethod BUILD {
    self.validate: 'username',
      { uniqueness => { scope => :tenant_id, conditions => { is_active => True } } }
  }
}

GLOBAL::<Voter> := Voter;
GLOBAL::<Donor> := Donor;
