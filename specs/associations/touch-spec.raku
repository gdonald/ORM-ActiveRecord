use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::Magazine;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'belongs-to touch', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'bumps parent updated_at on child create', {
    my $mag = Magazine.create({title => 'main'});
    my $u-orig = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];
    sleep 1.05;
    Article.create({title => 'a', magazine_id => $mag.id});
    my $u-after = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

    expect($u-after.Str gt $u-orig.Str).to.be-truthy;
  }

  it 'populates the named touch column', {
    my $mag = Magazine.create({title => 'main'});
    sleep 1.05;
    Article.create({title => 'a', magazine_id => $mag.id});
    my $r-after = DB.shared.exec("SELECT reviewed_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

    expect($r-after.defined).to.be-truthy;
  }

  it 'bumps parent updated_at on child destroy', {
    my $mag = Magazine.create({title => 'main'});
    sleep 1.05;
    my $art = Article.create({title => 'b', magazine_id => $mag.id});
    my $u-pre = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];
    sleep 1.05;
    $art.destroy;
    my $u-post = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

    expect($u-post.Str gt $u-pre.Str).to.be-truthy;
  }

  context 'child update', {
    it 'bumps parent updated_at', {
      my $mag = Magazine.create({title => 'main'});
      Article.create({title => 'a', magazine_id => $mag.id});
      sleep 1.05;
      my $art-up = Article.find-by({title => 'a'});
      my $u-pre = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];
      $art-up.update({title => 'a2'});
      my $u-post = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

      expect($u-post.Str gt $u-pre.Str).to.be-truthy;
    }

    it 'bumps named touch column', {
      my $mag = Magazine.create({title => 'main'});
      Article.create({title => 'a', magazine_id => $mag.id});
      sleep 1.05;
      my $art-up = Article.find-by({title => 'a'});
      my $r-pre = DB.shared.exec("SELECT reviewed_at FROM magazines WHERE id = " ~ $mag.id)[0][0];
      $art-up.update({title => 'a2'});
      my $r-post = DB.shared.exec("SELECT reviewed_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

      expect($r-post.Str gt $r-pre.Str).to.be-truthy;
    }
  }

  it 'is a no-op when no parent FK', {
    my $orphan = Article.create({title => 'lonely'});

    expect($orphan.id).to.be-greater-than(0);
  }

  it 'update-column bypasses touch', {
    my $mag = Magazine.create({title => 'main'});
    Article.create({title => 'a', magazine_id => $mag.id});
    sleep 1.05;
    my $art-up = Article.find-by({title => 'a'});
    my $u-pre = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];
    $art-up.update-column('title', 'a3');
    my $u-post = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag.id)[0][0];

    expect($u-post.Str).to.eq($u-pre.Str);
  }

  it 'reassigning FK bumps the new parent', {
    my $mag-a = Magazine.create({title => 'A'});
    my $mag-b = Magazine.create({title => 'B'});
    sleep 1.05;
    my $mover = Article.create({title => 'm', magazine_id => $mag-a.id});
    my $b-before = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag-b.id)[0][0];
    sleep 1.05;
    $mover.update({magazine_id => $mag-b.id});
    my $b-after = DB.shared.exec("SELECT updated_at FROM magazines WHERE id = " ~ $mag-b.id)[0][0];

    expect($b-after.Str gt $b-before.Str).to.be-truthy;
  }
}
