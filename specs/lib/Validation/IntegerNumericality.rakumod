use ORM::ActiveRecord::Model;

unit module Validation::IntegerNumericality;

class Book is Model is export {
  submethod BUILD {
    self.validate: 'title', { :presence }
    self.validate: 'pages', { :presence, numericality => { lt => 400 } }
    self.validate: 'sentences', { :presence, numericality => { gt => 1000 } }
    self.validate: 'words', { :presence, numericality => { in => 2000..5000 } }
    self.validate: 'periods', { :presence, numericality => { gte => 1000 } }
    self.validate: 'commas', { :presence, numericality => { lte => 200 } }
  }
}

GLOBAL::<Book> := Book;
