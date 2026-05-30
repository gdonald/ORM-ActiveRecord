use ORM::ActiveRecord::Model;

unit module Models::Comment;

class Comment is Model is export {
  submethod BUILD {
    self.belongs-to: commentable => polymorphic => True;
  }
}

GLOBAL::<Comment> := Comment;
