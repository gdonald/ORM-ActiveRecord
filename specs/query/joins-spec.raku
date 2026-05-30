use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::User;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'joins', {
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
    Subscription.create({user => $alice, magazine => $time});
    Subscription.create({user => $bob,   magazine => $mad});
  }

  after-each {
    Subscription.destroy-all;
    User.destroy-all;
    Magazine.destroy-all;
  }

  it 'joins(string) on belongs_to includes all subscriptions', {
    expect(Subscription.joins('user').count).to.eq(3);
  }

  it 'joins(:assoc) on has_many counts join rows', {
    expect(User.joins(:subscriptions).count).to.eq(3);
  }

  it 'joins(:through-assoc) joins through the join table', {
    expect(User.joins(:magazines).count).to.eq(3);
  }

  it 'joins + distinct returns base record count', {
    expect(User.joins(:subscriptions).distinct.count).to.eq(2);
  }

  it 'joins(raw SQL) emits the literal JOIN clause', {
    my $raw = 'INNER JOIN subscriptions ON subscriptions.user_id = users.id';

    expect(User.joins($raw).count).to.eq(3);
  }

  it 'nested joins recurse through the chain', {
    expect(User.joins(:subscriptions(:magazine)).count).to.eq(3);
  }

  it 'nested join filters via where on leaf table', {
    expect(User.joins(:subscriptions(:magazine)).where({magazines => {title => 'Mad'}}).distinct.count).to.eq(2);
  }

  it 'left-outer-joins keeps users with no subscriptions', {
    expect(User.left-outer-joins(:subscriptions).count).to.eq(4);
  }

  it 'left-outer-joins + distinct returns every user', {
    expect(User.left-outer-joins(:subscriptions).distinct.count).to.eq(3);
  }

  it 'where(table => {col => val}) filters on joined table for Alice', {
    expect(Subscription.joins(:user).where({users => {fname => 'Alice'}}).count).to.eq(2);
  }

  it 'nested-hash where narrows via joined column for Bob', {
    expect(Subscription.joins(:user).where({users => {fname => 'Bob'}}).count).to.eq(1);
  }

  it 'nested-hash where works with positive match for Alice', {
    expect(Subscription.joins(:user).where({users => {fname => 'Alice'}}).count).to.eq(2);
  }

  context 'joins-values', {
    it 'reflects added join', {
      my $q = User.joins(:subscriptions);

      expect($q.joins-values.elems).to.eq(1);
    }

    it 'stores rendered join SQL', {
      my $q = User.joins(:subscriptions);

      expect($q.joins-values[0].contains('INNER JOIN subscriptions')).to.be-truthy;
    }
  }

  it 'unscope(:joins) returns to plain query', {
    expect(User.joins(:subscriptions).unscope(:joins).all.elems).to.eq(3);
  }

  it 'merge propagates joins from other relation', {
    my $j = User.joins(:subscriptions);
    my $f = User.where({fname => 'Alice'});

    expect($f.merge($j).distinct.count).to.eq(1);
  }

  it 'where on base column under join is auto-qualified', {
    expect(User.joins(:subscriptions).where({fname => 'Alice'}).distinct.count).to.eq(1);
  }
}
