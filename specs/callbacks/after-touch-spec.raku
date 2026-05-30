use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::AfterTouch;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'after-touch callback', {
  before-each {
    Article.destroy-all;
  }

  after-each {
    Article.destroy-all;
  }

  it 'does not fire on create', {
    my $a = Article.create({ title => 'hello', body => 'world' });

    expect($a.touch-count).to.eq(0);
  }

  it 'fires once after touch', {
    my $a = Article.create({ title => 'hello', body => 'world' });
    $a.touch;

    expect($a.touch-count).to.eq(1);
  }

  it 'fires again after another touch', {
    my $a = Article.create({ title => 'hello', body => 'world' });
    $a.touch;
    $a.touch;

    expect($a.touch-count).to.eq(2);
  }
}
