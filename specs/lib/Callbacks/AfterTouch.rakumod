use ORM::ActiveRecord::Model;

unit module Callbacks::AfterTouch;

class Article is Model is export {
  has Int $.touch-count is rw = 0;

  submethod BUILD {
    self.after-touch: -> { self.touch-count++ };
  }
}

GLOBAL::<Article> := Article;
