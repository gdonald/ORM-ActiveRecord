use ORM::ActiveRecord::Model;

unit module Models::Track;

class Track is Model is export {
  submethod BUILD {
    self.belongs-to: studio => %(
      class-name      => 'Studio',
      strict-loading  => True,
      optional        => True,
    );
  }
}

GLOBAL::<Track> := Track;
