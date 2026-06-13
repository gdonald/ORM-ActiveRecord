use ORM::ActiveRecord::Model;

unit module Models::Signboard;

class Signboard is Model is export {
  submethod BUILD {
    self.belongs-to: workshop => class-name => 'Workshop';

    self.validate: 'slogan', { :presence };
  }
}

GLOBAL::<Signboard> := Signboard;
