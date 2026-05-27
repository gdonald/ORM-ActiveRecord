use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class TsArticle is Model {
  method table-name { 'articles' }
}

describe 'timestamps', {
  before-each {
    TsArticle.destroy-all;
  }

  after-each {
    TsArticle.destroy-all;
  }

  context 'on insert', {
    my $article;

    before-each {
      $article = TsArticle.create({ title => 'Hello', body => 'world' });
    }

    it 'assigns an id', {
      expect($article.id).to.be-greater-than(0);
    }

    it 'populates created_at as a DateTime', {
      expect($article.created_at).to.be-a(DateTime);
    }

    it 'populates updated_at as a DateTime', {
      expect($article.updated_at).to.be-a(DateTime);
    }
  }

  context 'on update', {
    my $article;
    my $original-created;
    my $original-updated;
    my $reloaded;

    before-all {
      TsArticle.destroy-all;
      $article          = TsArticle.create({ title => 'Hello', body => 'world' });
      $original-created = $article.created_at;
      $original-updated = $article.updated_at;

      sleep 1.1;

      $article.update({ title => 'Hello, World' });
      $reloaded = TsArticle.find($article.id);
    }

    it 'preserves created_at', {
      expect($reloaded.created_at.posix).to.eq($original-created.posix);
    }

    it 'advances updated_at', {
      expect($reloaded.updated_at.posix).to.be-greater-than($original-updated.posix);
    }

    it 'persists the new title', {
      expect($reloaded.title).to.eq('Hello, World');
    }
  }
}
