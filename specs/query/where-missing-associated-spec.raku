use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use Models::User;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'where.missing / where.associated', {
  my ($alice, $bob, $carol, $mad, $time);

  before-each {
    Subscription.destroy-all;
    User.destroy-all;
    Magazine.destroy-all;

    $alice = User.create({fname => 'Alice', lname => 'A'});
    $bob   = User.create({fname => 'Bob',   lname => 'B'});
    $carol = User.create({fname => 'Carol', lname => 'C'});

    $mad  = Magazine.create({title => 'Mad'});
    $time = Magazine.create({title => 'Time'});

    Subscription.create({user => $alice, magazine => $mad});
    Subscription.create({user => $bob,   magazine => $time});
  }

  after-each {
    Subscription.destroy-all;
    User.destroy-all;
    Magazine.destroy-all;
  }

  context 'where.missing(:has-many)', {
    it 'finds users with no rows', {
      my @no-subs = User.where.missing(:subscriptions).order('fname').all;

      expect(@no-subs.elems).to.eq(1);
    }

    it 'returned the user with no subscriptions', {
      my @no-subs = User.where.missing(:subscriptions).order('fname').all;

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
      my @no-user = Subscription.where.missing(:user).all;

      expect(@no-user.elems).to.eq(1);
    }

    it 'returned the orphan subscription', {
      my @no-user = Subscription.where.missing(:user).all;

      expect(@no-user[0].id).to.be-greater-than(0);
    }
  }

  context 'where.associated(:has-many)', {
    it 'finds users with rows', {
      my @subbed = User.where.associated(:subscriptions).distinct.order('fname').all;

      expect(@subbed.elems).to.eq(2);
    }

    it 'returned the subscribed users', {
      my @subbed = User.where.associated(:subscriptions).distinct.order('fname').all;

      expect(@subbed.map({ .fname }).join(',')).to.eq('Alice,Bob');
    }
  }

  it 'where.associated narrows to FK-present rows', {
    expect(Subscription.where.associated(:user).count).to.eq(2);
  }

  it 'count honors missing', {
    expect(User.where.missing(:subscriptions).count).to.eq(1);
  }

  it 'count honors associated', {
    expect(User.where.associated(:subscriptions).distinct.count).to.eq(2);
  }

  it 'missing through has_many :through finds users with no magazines', {
    expect(User.where.missing(:magazines).count).to.eq(1);
  }

  it 'Model.missing shortcut works', {
    expect(User.missing(:subscriptions).count).to.eq(1);
  }

  it 'Model.associated shortcut works', {
    expect(User.associated(:subscriptions).distinct.count).to.eq(2);
  }
}
