use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::InitializeFind;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'initialize and find callbacks', {
  before-each {
    Article.destroy-all;
  }

  after-each {
    Article.destroy-all;
  }

  context 'new()', {
    it 'fires after-initialize', {
      my $a = Article.new(:id(0));

      expect($a.init-count).to.eq(1);
    }

    it 'does not fire after-find', {
      my $a = Article.new(:id(0));

      expect($a.find-count).to.eq(0);
    }
  }

  context 'build()', {
    it 'fires after-initialize', {
      my $a = Article.build({ title => 't', body => 'b' });

      expect($a.init-count).to.eq(1);
    }

    it 'does not fire after-find', {
      my $a = Article.build({ title => 't', body => 'b' });

      expect($a.find-count).to.eq(0);
    }
  }

  context 'loading from DB', {
    before-each {
      my $a = Article.build({ title => 't', body => 'b' });
      $a.save;
    }

    it 'fires after-initialize', {
      my $first = Article.first;

      expect($first.init-count).to.eq(1);
    }

    it 'fires after-find', {
      my $first = Article.first;

      expect($first.find-count).to.eq(1);
    }
  }
}
