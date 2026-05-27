use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PiuBook is Model {
  method table-name { 'books' }

  submethod BUILD {
    self.validate: 'title',     { :presence, :if => { self.returns-true } }
    self.validate: 'pages',     { :presence, :if => { self.returns-false } }
    self.validate: 'sentences', { :presence, :unless => { self.returns-true } }
    self.validate: 'words',     { :presence, :unless => { self.returns-false } }
  }

  method returns-true  { True }
  method returns-false { False }
}

describe 'presence with :if and :unless', {
  after-each { PiuBook.destroy-all }

  it 'is not valid', {
    my $book = PiuBook.build;
    expect($book.is-valid).to.be-falsy;
  }

  it 'fires title presence when :if returns true', {
    my $book = PiuBook.build;
    $book.is-valid;
    expect($book.errors.title[0]).to.eq('must be present');
  }

  it 'skips pages presence when :if returns false', {
    my $book = PiuBook.build;
    $book.is-valid;
    expect($book.errors.pages).to.be-falsy;
  }

  it 'skips sentences presence when :unless returns true', {
    my $book = PiuBook.build;
    $book.is-valid;
    expect($book.errors.sentences).to.be-falsy;
  }

  it 'fires words presence when :unless returns false', {
    my $book = PiuBook.build;
    $book.is-valid;
    expect($book.errors.words[0]).to.eq('must be present');
  }
}
