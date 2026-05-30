use ORM::ActiveRecord::Model;

unit module Models::Belonging;

class Belonging is Model is export {
  my Int $destroy-count = 0;
  method destroy-count { $destroy-count }
  method reset-destroy-count { $destroy-count = 0 }

  submethod BUILD {
    self.before-destroy: -> { ++$destroy-count };
  }
}

GLOBAL::<Belonging> := Belonging;
