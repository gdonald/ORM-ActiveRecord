use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::AfterUpdate;
use Models::Log;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'after-update callback', {
  before-each {
    Client.destroy-all;
    Log.destroy-all;
  }

  after-each {
    Client.destroy-all;
    Log.destroy-all;
  }

  it 'does not fire on create', {
    Client.create({ email => 'fred@aol.com' });

    expect(Log.count).to.eq(0);
  }

  it 'fires on update', {
    my $client = Client.create({ email => 'fred@aol.com' });

    $client.email = 'barney@compuserve.net';
    $client.save;

    expect(Log.count).to.eq(1);
  }
}
