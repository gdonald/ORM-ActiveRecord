use ORM::ActiveRecord::Model;

unit module Models::Passport;

class Passport is Model is export {
  submethod BUILD {
    self.belongs-to: owner => %(
      class-name  => 'User',
      foreign-key => 'owner_id',
      optional    => True,
    );
  }
}

GLOBAL::<Passport> := Passport;
