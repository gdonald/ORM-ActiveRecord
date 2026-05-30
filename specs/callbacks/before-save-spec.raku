use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::BeforeSave;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'before-save callback', {
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

  it 'lowercases email on update', {
    my $client = Client.create({ email => 'Fred@AOL.com' });

    $client.email = 'BARNEY@compuserve.NET';
    $client.save;

    expect($client.email).to.eq('barney@compuserve.net');
  }
}
