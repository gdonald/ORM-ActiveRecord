use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'timestamps', {
  before-each {
    Article.destroy-all;
  }

  after-each {
    Article.destroy-all;
  }

  context 'on insert', {
    my $article;

    before-each {
      $article = Article.create({ title => 'Hello', body => 'world' });
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

    it 'honors an explicitly provided created_at', {
      my $when = DateTime.new(2020, 1, 2, 3, 4, 5, :timezone(0));
      my $backdated = Article.create({ title => 'Old', body => 'x', created_at => $when });
      expect(Article.find($backdated.id).created_at.posix).to.eq($when.posix);
    }
  }

  context 'on update', {
    my $article;
    my $original-created;
    my $original-updated;
    my $reloaded;

    before-all {
      Article.destroy-all;
      $article          = Article.create({ title => 'Hello', body => 'world' });
      $original-created = $article.created_at;
      $original-updated = $article.updated_at;

      sleep 1.1;

      $article.update({ title => 'Hello, World' });
      $reloaded = Article.find($article.id);
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
