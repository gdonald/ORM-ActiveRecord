use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'DB.shared connection lifecycle', {
  it 'is connected after the first query', {
    my $db = DB.shared;
    $db.exec('SELECT 1');

    expect($db.is-connected).to.be-truthy;
  }

  it 'disconnects and returns True when a live handle existed', {
    my $db = DB.shared;
    $db.exec('SELECT 1') unless $db.is-connected;

    expect($db.disconnect).to.be-truthy;
  }

  it 'reports false from is-connected after a disconnect', {
    my $db = DB.shared;
    $db.exec('SELECT 1') unless $db.is-connected;
    $db.disconnect;

    expect($db.is-connected).to.be-falsy;
  }

  it 'returns False from a second consecutive disconnect', {
    my $db = DB.shared;
    $db.exec('SELECT 1') unless $db.is-connected;
    $db.disconnect;

    expect($db.disconnect).to.be-falsy;
  }

  it 'restores the connection after reconnect', {
    my $db = DB.shared;
    $db.disconnect;
    $db.reconnect;

    expect($db.is-connected).to.be-truthy;
  }

  it 'succeeds at a query after reconnect', {
    my $db = DB.shared;
    $db.disconnect;
    $db.reconnect;
    my @rows = $db.exec('SELECT 1');

    expect(@rows[0][0].Int).to.eq(1);
  }

  it 'is disconnected right before the auto-reconnect probe', {
    my $db = DB.shared;
    $db.exec('SELECT 1') unless $db.is-connected;
    $db.disconnect;

    expect($db.is-connected).to.be-falsy;
  }

  it 'auto-reconnects when exec runs on a nil handle', {
    my $db = DB.shared;
    $db.exec('SELECT 1') unless $db.is-connected;
    $db.disconnect;
    my @rows2 = $db.exec('SELECT 2');

    expect(@rows2[0][0].Int).to.eq(2);
  }
}
