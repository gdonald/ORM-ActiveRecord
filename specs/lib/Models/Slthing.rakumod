use ORM::ActiveRecord::Model;

unit module Models::Slthing;

class Slthing is Model is export {
  submethod BUILD {
    self.belongs-to: slowner => %(
      class-name      => 'Slowner',
      strict-loading  => True,
      optional        => True,
    );
  }
}

GLOBAL::<Slthing> := Slthing;
