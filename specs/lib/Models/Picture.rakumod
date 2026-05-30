use ORM::ActiveRecord::Model;

unit module Models::Picture;

class Picture is Model is export {
  submethod BUILD {
    self.belongs-to: imageable => :polymorphic;
  }
}

GLOBAL::<Picture> := Picture;
