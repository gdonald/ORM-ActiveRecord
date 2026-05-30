use ORM::ActiveRecord::Model;

unit module Models::Town;

class Town is Model is export {
  submethod BUILD {
    self.belongs-to: region => %(
      class-name  => 'Region',
      primary-key => 'code',
      foreign-key => 'region_code',
    );
  }
}

GLOBAL::<Town> := Town;
