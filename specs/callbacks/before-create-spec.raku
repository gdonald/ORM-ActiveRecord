use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BcClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-create: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

describe 'before-create callback', {
  before-each {
    BcClient.destroy-all;
  }

  after-each {
    BcClient.destroy-all;
  }

  it 'lowercases email on create', {
    my $client = BcClient.create({ email => 'Fred@AOL.com' });

    expect($client.email).to.eq('fred@aol.com');
  }

  it 'does not fire on subsequent save', {
    my $client = BcClient.create({ email => 'Fred@AOL.com' });

    $client.email = 'BARNEY@compuserve.NET';
    $client.save;

    expect($client.email).to.eq('BARNEY@compuserve.NET');
  }
}
