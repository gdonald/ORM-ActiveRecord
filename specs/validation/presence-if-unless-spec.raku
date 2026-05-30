use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::PresenceIfUnless;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'presence with :if and :unless', {
  after-each { Book.destroy-all }

  it 'is not valid', {
    my $book = Book.build;
    expect($book.is-valid).to.be-falsy;
  }

  it 'fires title presence when :if returns true', {
    my $book = Book.build;
    $book.is-valid;
    expect($book.errors.title[0]).to.eq('must be present');
  }

  it 'skips pages presence when :if returns false', {
    my $book = Book.build;
    $book.is-valid;
    expect($book.errors.pages).to.be-falsy;
  }

  it 'skips sentences presence when :unless returns true', {
    my $book = Book.build;
    $book.is-valid;
    expect($book.errors.sentences).to.be-falsy;
  }

  it 'fires words presence when :unless returns false', {
    my $book = Book.build;
    $book.is-valid;
    expect($book.errors.words[0]).to.eq('must be present');
  }
}
