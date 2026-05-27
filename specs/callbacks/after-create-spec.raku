use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AcLog is Model {
  method table-name { 'logs' }
};

class AcClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-create: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was created';
    AcLog.create({:$log});
  }
}

describe 'after-create callback', {
  before-each {
    AcClient.destroy-all;
    AcLog.destroy-all;
  }

  after-each {
    AcClient.destroy-all;
    AcLog.destroy-all;
  }

  it 'fires once on create', {
    AcClient.create({ email => 'fred@aol.com' });

    expect(AcLog.count).to.eq(1);
  }

  it 'does not fire on subsequent save', {
    my $client = AcClient.create({ email => 'fred@aol.com' });

    $client.email = 'barney@compuserve.net';
    $client.save;

    expect(AcLog.count).to.eq(1);
  }
}
