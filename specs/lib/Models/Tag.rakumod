use ORM::ActiveRecord::Model;

unit module Models::Tag;

class Tag is Model is export {
  submethod BUILD {
    self.has-and-belongs-to-many: posts => class-name => 'Post';
  }
}

GLOBAL::<Tag> := Tag;
