use ORM::ActiveRecord::Model;

unit module Validation::PresenceIfUnless;

class Book is Model is export {
  submethod BUILD {
    self.validate: 'title', { :presence, :if => { self.returns-true } }
    self.validate: 'pages', { :presence, :if => { self.returns-false } }
    self.validate: 'sentences', { :presence, :unless => { self.returns-true } }
    self.validate: 'words', { :presence, :unless => { self.returns-false } }
  }

  method returns-true { True }
  method returns-false { False }
}

GLOBAL::<Book> := Book;
