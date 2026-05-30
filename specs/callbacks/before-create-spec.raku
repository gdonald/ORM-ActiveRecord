use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::BeforeCreate;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'before-create callback', {
  before-each {
    Client.destroy-all;
  }

  after-each {
    Client.destroy-all;
  }

  it 'lowercases email on create', {
    my $client = Client.create({ email => 'Fred@AOL.com' });

    expect($client.email).to.eq('fred@aol.com');
  }

  it 'does not fire on subsequent save', {
    my $client = Client.create({ email => 'Fred@AOL.com' });

    $client.email = 'BARNEY@compuserve.NET';
    $client.save;

    expect($client.email).to.eq('BARNEY@compuserve.NET');
  }
}
