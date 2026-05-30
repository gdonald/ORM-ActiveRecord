use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::AfterCreate;
use Models::Log;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'after-create callback', {
  before-each {
    Client.destroy-all;
    Log.destroy-all;
  }

  after-each {
    Client.destroy-all;
    Log.destroy-all;
  }

  it 'fires once on create', {
    Client.create({ email => 'fred@aol.com' });

    expect(Log.count).to.eq(1);
  }

  it 'does not fire on subsequent save', {
    my $client = Client.create({ email => 'fred@aol.com' });

    $client.email = 'barney@compuserve.net';
    $client.save;

    expect(Log.count).to.eq(1);
  }
}
