use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;

describe 'streaming a statement row by row', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:three-users, {
    User.create({fname => 'ann',  lname => 'x'});
    User.create({fname => 'bob',  lname => 'y'});
    User.create({fname => 'cara', lname => 'z'});
    3;
  });

  let(:select-names, {
    $adapter.sanitize-sql('SELECT fname FROM users ORDER BY fname')
  });

  it 'reports how many rows it handed over', {
    three-users;

    expect($adapter.stream-stmt(select-names, -> $row { })).to.eq(3);
  }

  it 'hands over every row in order', {
    three-users;
    my @seen;
    $adapter.stream-stmt(select-names, -> $row { @seen.push: $row[0] });

    expect(@seen.join(',')).to.eq('ann,bob,cara');
  }

  it 'hands over hash rows when asked', {
    three-users;
    my @seen;
    $adapter.stream-stmt(select-names, -> %row { @seen.push: %row<fname> }, :hash);

    expect(@seen.join(',')).to.eq('ann,bob,cara');
  }

  it 'hands over nothing for a result set with no rows', {
    three-users;
    my @seen;
    my $count = $adapter.stream-stmt(
      $adapter.sanitize-sql-array(['SELECT fname FROM users WHERE fname = ?', 'nobody']),
      -> $row { @seen.push: $row[0] },
    );

    expect($count).to.eq(0);
  }

  it 'leaves the connection usable afterward', {
    three-users;
    $adapter.stream-stmt(select-names, -> $row { });

    expect($adapter.exec('SELECT 1')[0][0].Int).to.eq(1);
  }

  it 'leaves the connection usable after the block throws', {
    three-users;

    try $adapter.stream-stmt(select-names, -> $row { die 'stop' });

    expect($adapter.exec('SELECT 1')[0][0].Int).to.eq(1);
  }

  it 'does not cache the statement it streamed', {
    three-users;
    my $conn = DB.shared.build-connection;
    LEAVE $conn.disconnect;
    $conn.prepared-statements = True;

    $conn.stream-stmt($conn.sanitize-sql('SELECT fname FROM users ORDER BY fname'), -> $row { });

    expect($conn.cached-statement-count).to.eq(0);
  }

  it 'refuses a write while writes are prohibited', {
    three-users;

    expect({
      $adapter.while-preventing-writes({
        $adapter.stream-stmt($adapter.sanitize-sql('DELETE FROM users'), -> $row { });
      });
    }).to.throw;
  }
}
