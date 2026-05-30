use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::BeforeUpdate;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'before-update callback', {
  before-each {
    Client.destroy-all;
  }

  after-each {
    Client.destroy-all;
  }

  it 'does not fire on create', {
    my $client = Client.create({ email => 'Fred@AOL.com' });

    expect($client.email).to.eq('Fred@AOL.com');
  }

  it 'lowercases email on save', {
    my $client = Client.create({ email => 'Fred@AOL.com' });
    $client.save;

    expect($client.email).to.eq('fred@aol.com');
  }
}
