use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BuClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.before-update: -> { self.lowercase-email };
  }

  method lowercase-email {
    self.email .= lc;
  }
}

describe 'before-update callback', {
  before-each {
    BuClient.destroy-all;
  }

  after-each {
    BuClient.destroy-all;
  }

  it 'does not fire on create', {
    my $client = BuClient.create({ email => 'Fred@AOL.com' });

    expect($client.email).to.eq('Fred@AOL.com');
  }

  it 'lowercases email on save', {
    my $client = BuClient.create({ email => 'Fred@AOL.com' });
    $client.save;

    expect($client.email).to.eq('fred@aol.com');
  }
}
