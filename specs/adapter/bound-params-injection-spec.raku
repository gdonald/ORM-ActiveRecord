use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'bound-parameters guard against SQL injection', {
  before-each {
    User.destroy-all;
  }

  after-each {
    User.destroy-all;
  }

  it 'creates two users without incident', {
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});

    expect(User.count).to.eq(2);
  }

  it 'treats an injection-style WHERE payload as a literal and matches nothing', {
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});

    my $payload = q{foo' OR '1'='1};
    my @rows = User.where({fname => $payload}).all;

    expect(@rows.elems).to.eq(0);
  }

  it 'round-trips a literal apostrophe through WHERE binds', {
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => q{O'Neill}, lname => 'Sam'});

    expect(User.where({fname => q{O'Neill}}).count).to.eq(1);
  }

  it 'leaves three rows present after the apostrophe insert', {
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => q{O'Neill}, lname => 'Sam'});

    expect(User.count).to.eq(3);
  }
}
