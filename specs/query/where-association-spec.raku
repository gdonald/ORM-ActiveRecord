use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::User;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'where with association', {
  my ($alice, $bob, $mad, $time);

  before-each {
    Subscription.destroy-all;
    User.destroy-all;
    Magazine.destroy-all;

    $alice = User.create({fname => 'Alice', lname => 'A'});
    $bob   = User.create({fname => 'Bob',   lname => 'B'});

    $mad  = Magazine.create({title => 'Mad'});
    $time = Magazine.create({title => 'Time'});

    Subscription.create({user => $alice, magazine => $mad});
    Subscription.create({user => $alice, magazine => $time});
    Subscription.create({user => $bob,   magazine => $mad});
  }

  after-each {
    Subscription.destroy-all;
    User.destroy-all;
    Magazine.destroy-all;
  }

  it 'where(assoc: instance) finds rows by FK', {
    my @alice-subs = Subscription.where({user => $alice}).all;

    expect(@alice-subs.elems).to.eq(2);
  }

  it 'where(assoc: instance) on second instance', {
    my @bob-subs = Subscription.where({user => $bob}).all;

    expect(@bob-subs.elems).to.eq(1);
  }

  it 'count honors instance shorthand', {
    expect(Subscription.where({user => $alice}).count).to.eq(2);
  }

  it 'two assoc instances ANDed together', {
    my @one = Subscription.where({user => $alice, magazine => $time}).all;

    expect(@one.elems).to.eq(1);
  }

  it 'where(assoc: @instances) emits IN with their ids', {
    my @both-users = Subscription.where({user => [$alice, $bob]}).all;

    expect(@both-users.elems).to.eq(3);
  }

  it 'where.not(assoc: instance) excludes by FK', {
    my @not-alice = Subscription.where.not({user => $alice}).all;

    expect(@not-alice.elems).to.eq(1);
  }

  it 'raw user_id still works', {
    expect(Subscription.where({user_id => $alice.id}).count).to.eq(2);
  }

  it 'instance shorthand chains with another where', {
    my @chained = Subscription.where({magazine => $mad}).where({user => $alice}).all;

    expect(@chained.elems).to.eq(1);
  }

  it 'rewhere replaces the FK', {
    my @rewhered = Subscription.where({user => $alice}).rewhere({user => $bob}).all;

    expect(@rewhered.elems == 1 && @rewhered[0].user_id == $bob.id).to.be-truthy;
  }
}
