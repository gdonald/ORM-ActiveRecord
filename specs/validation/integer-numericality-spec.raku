use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class IntBook is Model {
  method table-name { 'books' }

  submethod BUILD {
    self.validate: 'title', { :presence }
    self.validate: 'pages', { :presence, numericality => { lt => 400 } }
    self.validate: 'sentences', { :presence, numericality => { gt => 1000 } }
    self.validate: 'words', { :presence, numericality => { in => 2000..5000 } }
    self.validate: 'periods', { :presence, numericality => { gte => 1000 } }
    self.validate: 'commas', { :presence, numericality => { lte => 200 } }
  }
}

sub valid-attrs {
  { title => 'Book Title', pages => 399, sentences => 1001, words => 2000, periods => 1000, commas => 200 }
}

describe 'integer numericality validator', {
  after-each { IntBook.destroy-all }

  context 'all-valid record via create', {
    it 'is valid', {
      my $book = IntBook.create(valid-attrs);
      expect($book.is-valid).to.be-truthy;
    }
  }

  context 'all-valid record via build', {
    it 'is valid', {
      my $book = IntBook.build(valid-attrs);
      expect($book.is-valid).to.be-truthy;
    }
  }

  context 'pages = 400 (lt 400 boundary)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.pages = 400;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "less than 400 required"', {
      my $book = IntBook.build(valid-attrs);
      $book.pages = 400;
      $book.is-invalid;
      expect($book.errors.pages[0]).to.eq('less than 400 required');
    }
  }

  context 'baseline build is still valid before tweaks', {
    it 'is valid', {
      my $book = IntBook.build(valid-attrs);
      expect($book.is-valid).to.be-truthy;
    }
  }

  context 'sentences = 1000 (gt 1000 boundary)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.sentences = 1000;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "more than 1000 required"', {
      my $book = IntBook.build(valid-attrs);
      $book.sentences = 1000;
      $book.is-invalid;
      expect($book.errors.sentences[0]).to.eq('more than 1000 required');
    }
  }

  context 'words = 1999 (under range)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.words = 1999;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "2000 to 5000 required"', {
      my $book = IntBook.build(valid-attrs);
      $book.words = 1999;
      $book.is-invalid;
      expect($book.errors.words[0]).to.eq('2000 to 5000 required');
    }
  }

  context 'words = 5001 (over range)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.words = 5001;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "2000 to 5000 required"', {
      my $book = IntBook.build(valid-attrs);
      $book.words = 5001;
      $book.is-invalid;
      expect($book.errors.words[0]).to.eq('2000 to 5000 required');
    }
  }

  context 'periods = 999 (under gte 1000)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.periods = 999;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "1000 or more required"', {
      my $book = IntBook.build(valid-attrs);
      $book.periods = 999;
      $book.is-invalid;
      expect($book.errors.periods[0]).to.eq('1000 or more required');
    }
  }

  context 'commas = 201 (over lte 200)', {
    it 'is invalid', {
      my $book = IntBook.build(valid-attrs);
      $book.commas = 201;
      expect($book.is-invalid).to.be-truthy;
    }

    it 'reports "200 or less required"', {
      my $book = IntBook.build(valid-attrs);
      $book.commas = 201;
      $book.is-invalid;
      expect($book.errors.commas[0]).to.eq('200 or less required');
    }
  }
}
