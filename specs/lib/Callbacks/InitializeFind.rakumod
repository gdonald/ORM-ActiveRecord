use ORM::ActiveRecord::Model;

unit module Callbacks::InitializeFind;

class Article is Model is export {
  has Int $.init-count is rw = 0;
  has Int $.find-count is rw = 0;

  submethod BUILD {
    self.after-initialize: -> { self.init-count++ };
    self.after-find:       -> { self.find-count++ };
  }
}

GLOBAL::<Article> := Article;
