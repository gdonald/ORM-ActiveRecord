use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WmSubscription {...}

class WmUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: subscriptions => class => WmSubscription;
    self.has-many: magazines => through => :subscriptions;
  }
}

class WmMagazine is Model {
  method table-name { 'magazines' }
}

class WmSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: user => class => WmUser;
    self.belongs-to: magazine => class => WmMagazine;
  }
}

describe 'where.missing / where.associated', {
  my ($alice, $bob, $carol, $mad, $time);

  before-each {
    WmSubscription.destroy-all;
    WmUser.destroy-all;
    WmMagazine.destroy-all;

    $alice = WmUser.create({fname => 'Alice', lname => 'A'});
    $bob   = WmUser.create({fname => 'Bob',   lname => 'B'});
    $carol = WmUser.create({fname => 'Carol', lname => 'C'});

    $mad  = WmMagazine.create({title => 'Mad'});
    $time = WmMagazine.create({title => 'Time'});

    WmSubscription.create({user => $alice, magazine => $mad});
    WmSubscription.create({user => $bob,   magazine => $time});
  }

  after-each {
    WmSubscription.destroy-all;
    WmUser.destroy-all;
    WmMagazine.destroy-all;
  }

  context 'where.missing(:has-many)', {
    it 'finds users with no rows', {
      my @no-subs = WmUser.where.missing(:subscriptions).order('fname').all;

      expect(@no-subs.elems).to.eq(1);
    }

    it 'returned the user with no subscriptions', {
      my @no-subs = WmUser.where.missing(:subscriptions).order('fname').all;

      expect(@no-subs[0].fname).to.eq('Carol');
    }
  }

  context 'where.missing on belongs-to with NULL FK', {
    before-each {
      DB.shared.exec('INSERT INTO subscriptions (user_id, magazine_id) VALUES (NULL, NULL)');
    }

    after-each {
      DB.shared.exec('DELETE FROM subscriptions WHERE user_id IS NULL');
    }

    it 'finds rows with NULL FK', {
      my @no-user = WmSubscription.where.missing(:user).all;

      expect(@no-user.elems).to.eq(1);
    }

    it 'returned the orphan subscription', {
      my @no-user = WmSubscription.where.missing(:user).all;

      expect(@no-user[0].id).to.be-greater-than(0);
    }
  }

  context 'where.associated(:has-many)', {
    it 'finds users with rows', {
      my @subbed = WmUser.where.associated(:subscriptions).distinct.order('fname').all;

      expect(@subbed.elems).to.eq(2);
    }

    it 'returned the subscribed users', {
      my @subbed = WmUser.where.associated(:subscriptions).distinct.order('fname').all;

      expect(@subbed.map({ .fname }).join(',')).to.eq('Alice,Bob');
    }
  }

  it 'where.associated narrows to FK-present rows', {
    expect(WmSubscription.where.associated(:user).count).to.eq(2);
  }

  it 'count honors missing', {
    expect(WmUser.where.missing(:subscriptions).count).to.eq(1);
  }

  it 'count honors associated', {
    expect(WmUser.where.associated(:subscriptions).distinct.count).to.eq(2);
  }

  it 'missing through has_many :through finds users with no magazines', {
    expect(WmUser.where.missing(:magazines).count).to.eq(1);
  }

  it 'Model.missing shortcut works', {
    expect(WmUser.missing(:subscriptions).count).to.eq(1);
  }

  it 'Model.associated shortcut works', {
    expect(WmUser.associated(:subscriptions).distinct.count).to.eq(2);
  }
}
