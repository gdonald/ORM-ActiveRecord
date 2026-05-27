use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AtArticle is Model {
  method table-name { 'articles' }

  has Int $.touch-count is rw = 0;

  submethod BUILD {
    self.after-touch: -> { self.touch-count++ };
  }
}

describe 'after-touch callback', {
  before-each {
    AtArticle.destroy-all;
  }

  after-each {
    AtArticle.destroy-all;
  }

  it 'does not fire on create', {
    my $a = AtArticle.create({ title => 'hello', body => 'world' });

    expect($a.touch-count).to.eq(0);
  }

  it 'fires once after touch', {
    my $a = AtArticle.create({ title => 'hello', body => 'world' });
    $a.touch;

    expect($a.touch-count).to.eq(1);
  }

  it 'fires again after another touch', {
    my $a = AtArticle.create({ title => 'hello', body => 'world' });
    $a.touch;
    $a.touch;

    expect($a.touch-count).to.eq(2);
  }
}
