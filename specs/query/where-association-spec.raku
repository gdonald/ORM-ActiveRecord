use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WasSubscription {...}

class WasUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: subscriptions => class => WasSubscription;
  }
}

class WasMagazine is Model {
  method table-name { 'magazines' }
}

class WasSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: user => class => WasUser;
    self.belongs-to: magazine => class => WasMagazine;
  }
}

describe 'where with association', {
  my ($alice, $bob, $mad, $time);

  before-each {
    WasSubscription.destroy-all;
    WasUser.destroy-all;
    WasMagazine.destroy-all;

    $alice = WasUser.create({fname => 'Alice', lname => 'A'});
    $bob   = WasUser.create({fname => 'Bob',   lname => 'B'});

    $mad  = WasMagazine.create({title => 'Mad'});
    $time = WasMagazine.create({title => 'Time'});

    WasSubscription.create({user => $alice, magazine => $mad});
    WasSubscription.create({user => $alice, magazine => $time});
    WasSubscription.create({user => $bob,   magazine => $mad});
  }

  after-each {
    WasSubscription.destroy-all;
    WasUser.destroy-all;
    WasMagazine.destroy-all;
  }

  it 'where(assoc: instance) finds rows by FK', {
    my @alice-subs = WasSubscription.where({user => $alice}).all;

    expect(@alice-subs.elems).to.eq(2);
  }

  it 'where(assoc: instance) on second instance', {
    my @bob-subs = WasSubscription.where({user => $bob}).all;

    expect(@bob-subs.elems).to.eq(1);
  }

  it 'count honors instance shorthand', {
    expect(WasSubscription.where({user => $alice}).count).to.eq(2);
  }

  it 'two assoc instances ANDed together', {
    my @one = WasSubscription.where({user => $alice, magazine => $time}).all;

    expect(@one.elems).to.eq(1);
  }

  it 'where(assoc: @instances) emits IN with their ids', {
    my @both-users = WasSubscription.where({user => [$alice, $bob]}).all;

    expect(@both-users.elems).to.eq(3);
  }

  it 'where.not(assoc: instance) excludes by FK', {
    my @not-alice = WasSubscription.where.not({user => $alice}).all;

    expect(@not-alice.elems).to.eq(1);
  }

  it 'raw user_id still works', {
    expect(WasSubscription.where({user_id => $alice.id}).count).to.eq(2);
  }

  it 'instance shorthand chains with another where', {
    my @chained = WasSubscription.where({magazine => $mad}).where({user => $alice}).all;

    expect(@chained.elems).to.eq(1);
  }

  it 'rewhere replaces the FK', {
    my @rewhered = WasSubscription.where({user => $alice}).rewhere({user => $bob}).all;

    expect(@rewhered.elems == 1 && @rewhered[0].user_id == $bob.id).to.be-truthy;
  }
}
