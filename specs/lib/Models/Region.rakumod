use ORM::ActiveRecord::Model;

unit module Models::Region;

class Region is Model is export {
  submethod BUILD {
    self.has-many: towns => %(
      class-name  => 'Town',
      primary-key => 'code',
      foreign-key => 'region_code',
    );
  }
}

GLOBAL::<Region> := Region;
