use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::User;
use Models::Magazine;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

sub user-count(Int:D $id --> Int) {
  DB.shared.exec("SELECT articles_count FROM users WHERE id = $id")[0][0].Int;
}

sub magazine-count(Int:D $id --> Int) {
  DB.shared.exec("SELECT managed_articles_ct FROM magazines WHERE id = $id")[0][0].Int;
}

describe 'counter-cache', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'default column name on create', {
    it 'starts at 0', {
      my $user = User.create({fname => 'main'});
      expect(user-count($user.id)).to.eq(0);
    }

    it 'bumps default counter to 1', {
      my $user = User.create({fname => 'main'});
      Article.create({title => 'A', author_id => $user.id});
      expect(user-count($user.id)).to.eq(1);
    }

    it 'bumps to 2 on a second create', {
      my $user = User.create({fname => 'main'});
      Article.create({title => 'A', author_id => $user.id});
      Article.create({title => 'B', author_id => $user.id});
      expect(user-count($user.id)).to.eq(2);
    }
  }

  it 'bumps counter when assigning belongs-to instance', {
    my $user2 = User.create({fname => 'branch'});
    Article.create({title => 'C', counter-author => $user2});
    expect(user-count($user2.id)).to.eq(1);
  }

  context 'destroy', {
    it 'returns True', {
      my $user = User.create({fname => 'main'});
      my $art-d = Article.create({title => 'X', author_id => $user.id});
      expect($art-d.destroy).to.be-truthy;
    }

    it 'decrements counter', {
      my $user = User.create({fname => 'main'});
      Article.create({title => 'A', author_id => $user.id});
      Article.create({title => 'B', author_id => $user.id});
      my $art-d = Article.create({title => 'X', author_id => $user.id});
      $art-d.destroy;
      expect(user-count($user.id)).to.eq(2);
    }
  }

  context 'update with FK change', {
    it 'decrements old parent', {
      my $user = User.create({fname => 'main'});
      my $user2 = User.create({fname => 'branch'});
      my $art-mv = Article.create({title => 'Move', author_id => $user.id});
      $art-mv.update({author_id => $user2.id});
      expect(user-count($user.id)).to.eq(0);
    }

    it 'increments new parent', {
      my $user = User.create({fname => 'main'});
      my $user2 = User.create({fname => 'branch'});
      Article.create({title => 'C', author_id => $user2.id});
      my $art-mv = Article.create({title => 'Move', author_id => $user.id});
      $art-mv.update({author_id => $user2.id});
      expect(user-count($user2.id)).to.eq(2);
    }
  }

  it 'leaves counter alone on non-FK update', {
    my $user = User.create({fname => 'main'});
    Article.create({title => 'A', author_id => $user.id});
    my $art-still = Article.where({author_id => $user.id}).first;
    my $before = user-count($user.id);
    $art-still.update({title => 'renamed'});
    expect(user-count($user.id)).to.eq($before);
  }

  context 'update FK from 0 → set', {
    it 'does not bump on orphan create', {
      my $user = User.create({fname => 'main'});
      my $before = user-count($user.id);
      Article.create({title => 'Orphan'});
      expect(user-count($user.id)).to.eq($before);
    }

    it 'bumps new parent on adoption', {
      my $user = User.create({fname => 'main'});
      my $before = user-count($user.id);
      my $art-orphan = Article.create({title => 'Orphan'});
      $art-orphan.update({author_id => $user.id});
      expect(user-count($user.id)).to.eq($before + 1);
    }
  }

  it 'detaching to 0 decrements old parent', {
    my $user = User.create({fname => 'main'});
    my $art-orphan = Article.create({title => 'Orphan'});
    $art-orphan.update({author_id => $user.id});
    my $pre = user-count($user.id);
    $art-orphan.update({author_id => 0});
    expect(user-count($user.id)).to.eq($pre - 1);
  }

  context 'custom column name', {
    it 'starts at 0', {
      my $mag = Magazine.create({title => 'mag-a'});
      expect(magazine-count($mag.id)).to.eq(0);
    }

    it 'bumps on create', {
      my $mag = Magazine.create({title => 'mag-a'});
      Article.create({title => 'T1', magazine_id => $mag.id});
      expect(magazine-count($mag.id)).to.eq(1);
    }

    it 'bumps a second time', {
      my $mag = Magazine.create({title => 'mag-a'});
      Article.create({title => 'T1', magazine_id => $mag.id});
      Article.create({title => 'T2', magazine_id => $mag.id});
      expect(magazine-count($mag.id)).to.eq(2);
    }

    it 'destroy returns True', {
      my $mag = Magazine.create({title => 'mag-a'});
      my $art-t = Article.create({title => 'T1', magazine_id => $mag.id});
      expect($art-t.destroy).to.be-truthy;
    }

    it 'destroy decrements custom column', {
      my $mag = Magazine.create({title => 'mag-a'});
      my $art-t = Article.create({title => 'T1', magazine_id => $mag.id});
      Article.create({title => 'T2', magazine_id => $mag.id});
      $art-t.destroy;
      expect(magazine-count($mag.id)).to.eq(1);
    }
  }

  context 'both counters on the same child', {
    it 'bumps user counter', {
      my $userA = User.create({fname => 'A'});
      my $magA  = Magazine.create({title => 'MA'});
      Article.create({title => 'dual', author_id => $userA.id, magazine_id => $magA.id});
      expect(user-count($userA.id)).to.eq(1);
    }

    it 'bumps magazine counter', {
      my $userA = User.create({fname => 'A'});
      my $magA  = Magazine.create({title => 'MA'});
      Article.create({title => 'dual', author_id => $userA.id, magazine_id => $magA.id});
      expect(magazine-count($magA.id)).to.eq(1);
    }
  }

  it 'bare delete bypasses counter-cache', {
    my $userD = User.create({fname => 'D'});
    my $art-bare = Article.create({title => 'bare', author_id => $userD.id});
    $art-bare.delete;
    expect(user-count($userD.id)).to.eq(1);
  }
}
