use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BsClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-save: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

describe 'before-save callback', {
  before-each {
    BsClient.destroy-all;
  }

  after-each {
    BsClient.destroy-all;
  }

  it 'lowercases email on create', {
    my $client = BsClient.create({ email => 'Fred@AOL.com' });

    expect($client.email).to.eq('fred@aol.com');
  }

  it 'lowercases email on update', {
    my $client = BsClient.create({ email => 'Fred@AOL.com' });

    $client.email = 'BARNEY@compuserve.NET';
    $client.save;

    expect($client.email).to.eq('barney@compuserve.net');
  }
}
