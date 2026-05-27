use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class IfArticle is Model {
  method table-name { 'articles' }

  has Int $.init-count is rw = 0;
  has Int $.find-count is rw = 0;

  submethod BUILD {
    self.after-initialize: -> { self.init-count++ };
    self.after-find:       -> { self.find-count++ };
  }
}

describe 'initialize and find callbacks', {
  before-each {
    IfArticle.destroy-all;
  }

  after-each {
    IfArticle.destroy-all;
  }

  context 'new()', {
    it 'fires after-initialize', {
      my $a = IfArticle.new(:id(0));

      expect($a.init-count).to.eq(1);
    }

    it 'does not fire after-find', {
      my $a = IfArticle.new(:id(0));

      expect($a.find-count).to.eq(0);
    }
  }

  context 'build()', {
    it 'fires after-initialize', {
      my $a = IfArticle.build({ title => 't', body => 'b' });

      expect($a.init-count).to.eq(1);
    }

    it 'does not fire after-find', {
      my $a = IfArticle.build({ title => 't', body => 'b' });

      expect($a.find-count).to.eq(0);
    }
  }

  context 'loading from DB', {
    before-each {
      my $a = IfArticle.build({ title => 't', body => 'b' });
      $a.save;
    }

    it 'fires after-initialize', {
      my $first = IfArticle.first;

      expect($first.init-count).to.eq(1);
    }

    it 'fires after-find', {
      my $first = IfArticle.first;

      expect($first.find-count).to.eq(1);
    }
  }
}
