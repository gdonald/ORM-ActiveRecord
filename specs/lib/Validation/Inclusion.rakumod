use ORM::ActiveRecord::Model;

unit module Validation::Inclusion;

class Image is Model is export {
  submethod BUILD {
    self.validate: 'ext', { :presence, inclusion => { in => <gif jpeg jpg png> } }
  }
}

GLOBAL::<Image> := Image;
