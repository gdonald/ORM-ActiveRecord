use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AuLog is Model {
  method table-name { 'logs' }
};

class AuClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-update: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was updated';
    AuLog.create({:$log});
  }
}

describe 'after-update callback', {
  before-each {
    AuClient.destroy-all;
    AuLog.destroy-all;
  }

  after-each {
    AuClient.destroy-all;
    AuLog.destroy-all;
  }

  it 'does not fire on create', {
    AuClient.create({ email => 'fred@aol.com' });

    expect(AuLog.count).to.eq(0);
  }

  it 'fires on update', {
    my $client = AuClient.create({ email => 'fred@aol.com' });

    $client.email = 'barney@compuserve.net';
    $client.save;

    expect(AuLog.count).to.eq(1);
  }
}
