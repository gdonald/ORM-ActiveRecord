use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AsLog is Model {
  method table-name { 'logs' }
};

class AsClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.after-save: -> { self.log };
  }

  method log {
    my $log = self.email ~ ' was saved';
    AsLog.create({:$log});
  }
}

describe 'after-save callback', {
  before-each {
    AsClient.destroy-all;
    AsLog.destroy-all;
  }

  after-each {
    AsClient.destroy-all;
    AsLog.destroy-all;
  }

  it 'fires once on create', {
    AsClient.create({ email => 'fred@aol.com' });

    expect(AsLog.count).to.eq(1);
  }

  it 'fires again on update', {
    my $client = AsClient.create({ email => 'fred@aol.com' });

    $client.email = 'barney@compuserve.net';
    $client.save;

    expect(AsLog.count).to.eq(2);
  }
}
