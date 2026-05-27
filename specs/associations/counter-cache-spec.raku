use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

class Ccbook { ... }

class Ccshop is Model {
  submethod BUILD {
    self.has-many: ccbooks => %(class => Ccbook, foreign-key => 'ccshop_id');
  }
}

class Ccteam is Model {
  submethod BUILD {
    self.has-many: ccbooks => %(class => Ccbook, foreign-key => 'ccteam_id');
  }
}

class Ccbook is Model {
  submethod BUILD {
    self.belongs-to: ccshop => %(
      class         => Ccshop,
      counter-cache => True,
      optional      => True,
    );
    self.belongs-to: ccteam => %(
      class         => Ccteam,
      counter-cache => 'managed_books_ct',
      optional      => True,
    );
  }
}

sub cc-clean {
  clean-shared-tables;
}

sub shop-count(Int:D $id --> Int) {
  DB.shared.exec("SELECT ccbooks_count FROM ccshops WHERE id = $id")[0][0].Int;
}

sub team-count(Int:D $id --> Int) {
  DB.shared.exec("SELECT managed_books_ct FROM ccteams WHERE id = $id")[0][0].Int;
}

describe 'counter-cache', {
  before-each { cc-clean }
  after-each  { cc-clean }

  context 'default column name on create', {
    it 'starts at 0', {
      my $shop = Ccshop.create({name => 'main'});
      expect(shop-count($shop.id)).to.eq(0);
    }

    it 'bumps default counter to 1', {
      my $shop = Ccshop.create({name => 'main'});
      Ccbook.create({title => 'A', ccshop_id => $shop.id});
      expect(shop-count($shop.id)).to.eq(1);
    }

    it 'bumps to 2 on a second create', {
      my $shop = Ccshop.create({name => 'main'});
      Ccbook.create({title => 'A', ccshop_id => $shop.id});
      Ccbook.create({title => 'B', ccshop_id => $shop.id});
      expect(shop-count($shop.id)).to.eq(2);
    }
  }

  it 'bumps counter when assigning belongs-to instance', {
    my $shop2 = Ccshop.create({name => 'branch'});
    Ccbook.create({title => 'C', ccshop => $shop2});
    expect(shop-count($shop2.id)).to.eq(1);
  }

  context 'destroy', {
    it 'returns True', {
      my $shop = Ccshop.create({name => 'main'});
      my $book-d = Ccbook.create({title => 'X', ccshop_id => $shop.id});
      expect($book-d.destroy).to.be-truthy;
    }

    it 'decrements counter', {
      my $shop = Ccshop.create({name => 'main'});
      Ccbook.create({title => 'A', ccshop_id => $shop.id});
      Ccbook.create({title => 'B', ccshop_id => $shop.id});
      my $book-d = Ccbook.create({title => 'X', ccshop_id => $shop.id});
      $book-d.destroy;
      expect(shop-count($shop.id)).to.eq(2);
    }
  }

  context 'update with FK change', {
    it 'decrements old parent', {
      my $shop = Ccshop.create({name => 'main'});
      my $shop2 = Ccshop.create({name => 'branch'});
      my $book-mv = Ccbook.create({title => 'Move', ccshop_id => $shop.id});
      $book-mv.update({ccshop_id => $shop2.id});
      expect(shop-count($shop.id)).to.eq(0);
    }

    it 'increments new parent', {
      my $shop = Ccshop.create({name => 'main'});
      my $shop2 = Ccshop.create({name => 'branch'});
      Ccbook.create({title => 'C', ccshop_id => $shop2.id});
      my $book-mv = Ccbook.create({title => 'Move', ccshop_id => $shop.id});
      $book-mv.update({ccshop_id => $shop2.id});
      expect(shop-count($shop2.id)).to.eq(2);
    }
  }

  it 'leaves counter alone on non-FK update', {
    my $shop = Ccshop.create({name => 'main'});
    Ccbook.create({title => 'A', ccshop_id => $shop.id});
    my $book-still = Ccbook.where({ccshop_id => $shop.id}).first;
    my $before = shop-count($shop.id);
    $book-still.update({title => 'renamed'});
    expect(shop-count($shop.id)).to.eq($before);
  }

  context 'update FK from 0 → set', {
    it 'does not bump on orphan create', {
      my $shop = Ccshop.create({name => 'main'});
      my $before = shop-count($shop.id);
      Ccbook.create({title => 'Orphan'});
      expect(shop-count($shop.id)).to.eq($before);
    }

    it 'bumps new parent on adoption', {
      my $shop = Ccshop.create({name => 'main'});
      my $before = shop-count($shop.id);
      my $book-orphan = Ccbook.create({title => 'Orphan'});
      $book-orphan.update({ccshop_id => $shop.id});
      expect(shop-count($shop.id)).to.eq($before + 1);
    }
  }

  it 'detaching to 0 decrements old parent', {
    my $shop = Ccshop.create({name => 'main'});
    my $book-orphan = Ccbook.create({title => 'Orphan'});
    $book-orphan.update({ccshop_id => $shop.id});
    my $pre = shop-count($shop.id);
    $book-orphan.update({ccshop_id => 0});
    expect(shop-count($shop.id)).to.eq($pre - 1);
  }

  context 'custom column name', {
    it 'starts at 0', {
      my $team = Ccteam.create({name => 'team-a'});
      expect(team-count($team.id)).to.eq(0);
    }

    it 'bumps on create', {
      my $team = Ccteam.create({name => 'team-a'});
      Ccbook.create({title => 'T1', ccteam_id => $team.id});
      expect(team-count($team.id)).to.eq(1);
    }

    it 'bumps a second time', {
      my $team = Ccteam.create({name => 'team-a'});
      Ccbook.create({title => 'T1', ccteam_id => $team.id});
      Ccbook.create({title => 'T2', ccteam_id => $team.id});
      expect(team-count($team.id)).to.eq(2);
    }

    it 'destroy returns True', {
      my $team = Ccteam.create({name => 'team-a'});
      my $book-t = Ccbook.create({title => 'T1', ccteam_id => $team.id});
      expect($book-t.destroy).to.be-truthy;
    }

    it 'destroy decrements custom column', {
      my $team = Ccteam.create({name => 'team-a'});
      my $book-t = Ccbook.create({title => 'T1', ccteam_id => $team.id});
      Ccbook.create({title => 'T2', ccteam_id => $team.id});
      $book-t.destroy;
      expect(team-count($team.id)).to.eq(1);
    }
  }

  context 'both counters on the same child', {
    it 'bumps shop counter', {
      my $shopA = Ccshop.create({name => 'A'});
      my $teamA = Ccteam.create({name => 'TA'});
      Ccbook.create({title => 'dual', ccshop_id => $shopA.id, ccteam_id => $teamA.id});
      expect(shop-count($shopA.id)).to.eq(1);
    }

    it 'bumps team counter', {
      my $shopA = Ccshop.create({name => 'A'});
      my $teamA = Ccteam.create({name => 'TA'});
      Ccbook.create({title => 'dual', ccshop_id => $shopA.id, ccteam_id => $teamA.id});
      expect(team-count($teamA.id)).to.eq(1);
    }
  }

  it 'bare delete bypasses counter-cache', {
    my $shopD = Ccshop.create({name => 'D'});
    my $book-bare = Ccbook.create({title => 'bare', ccshop_id => $shopD.id});
    $book-bare.delete;
    expect(shop-count($shopD.id)).to.eq(1);
  }
}
