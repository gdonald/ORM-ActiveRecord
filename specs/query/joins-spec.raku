use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class JnSubscription {...}

class JnUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: subscriptions => class => JnSubscription;
    self.has-many: magazines => through => :subscriptions;
  }
}

class JnMagazine is Model {
  method table-name { 'magazines' }
}

class JnSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: user => class => JnUser;
    self.belongs-to: magazine => class => JnMagazine;
  }
}

describe 'joins', {
  my ($alice, $bob, $carol, $mad, $time);

  before-each {
    JnSubscription.destroy-all;
    JnUser.destroy-all;
    JnMagazine.destroy-all;

    $alice = JnUser.create({fname => 'Alice', lname => 'A'});
    $bob   = JnUser.create({fname => 'Bob',   lname => 'B'});
    $carol = JnUser.create({fname => 'Carol', lname => 'C'});

    $mad  = JnMagazine.create({title => 'Mad'});
    $time = JnMagazine.create({title => 'Time'});

    JnSubscription.create({user => $alice, magazine => $mad});
    JnSubscription.create({user => $alice, magazine => $time});
    JnSubscription.create({user => $bob,   magazine => $mad});
  }

  after-each {
    JnSubscription.destroy-all;
    JnUser.destroy-all;
    JnMagazine.destroy-all;
  }

  it 'joins(string) on belongs_to includes all subscriptions', {
    expect(JnSubscription.joins('user').count).to.eq(3);
  }

  it 'joins(:assoc) on has_many counts join rows', {
    expect(JnUser.joins(:subscriptions).count).to.eq(3);
  }

  it 'joins(:through-assoc) joins through the join table', {
    expect(JnUser.joins(:magazines).count).to.eq(3);
  }

  it 'joins + distinct returns base record count', {
    expect(JnUser.joins(:subscriptions).distinct.count).to.eq(2);
  }

  it 'joins(raw SQL) emits the literal JOIN clause', {
    my $raw = 'INNER JOIN subscriptions ON subscriptions.user_id = users.id';

    expect(JnUser.joins($raw).count).to.eq(3);
  }

  it 'nested joins recurse through the chain', {
    expect(JnUser.joins(:subscriptions(:magazine)).count).to.eq(3);
  }

  it 'nested join filters via where on leaf table', {
    expect(JnUser.joins(:subscriptions(:magazine)).where({magazines => {title => 'Mad'}}).distinct.count).to.eq(2);
  }

  it 'left-outer-joins keeps users with no subscriptions', {
    expect(JnUser.left-outer-joins(:subscriptions).count).to.eq(4);
  }

  it 'left-outer-joins + distinct returns every user', {
    expect(JnUser.left-outer-joins(:subscriptions).distinct.count).to.eq(3);
  }

  it 'where(table => {col => val}) filters on joined table for Alice', {
    expect(JnSubscription.joins(:user).where({users => {fname => 'Alice'}}).count).to.eq(2);
  }

  it 'nested-hash where narrows via joined column for Bob', {
    expect(JnSubscription.joins(:user).where({users => {fname => 'Bob'}}).count).to.eq(1);
  }

  it 'nested-hash where works with positive match for Alice', {
    expect(JnSubscription.joins(:user).where({users => {fname => 'Alice'}}).count).to.eq(2);
  }

  context 'joins-values', {
    it 'reflects added join', {
      my $q = JnUser.joins(:subscriptions);

      expect($q.joins-values.elems).to.eq(1);
    }

    it 'stores rendered join SQL', {
      my $q = JnUser.joins(:subscriptions);

      expect($q.joins-values[0].contains('INNER JOIN subscriptions')).to.be-truthy;
    }
  }

  it 'unscope(:joins) returns to plain query', {
    expect(JnUser.joins(:subscriptions).unscope(:joins).all.elems).to.eq(3);
  }

  it 'merge propagates joins from other relation', {
    my $j = JnUser.joins(:subscriptions);
    my $f = JnUser.where({fname => 'Alice'});

    expect($f.merge($j).distinct.count).to.eq(1);
  }

  it 'where on base column under join is auto-qualified', {
    expect(JnUser.joins(:subscriptions).where({fname => 'Alice'}).distinct.count).to.eq(1);
  }
}
