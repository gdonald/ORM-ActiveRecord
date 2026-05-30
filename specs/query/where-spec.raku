use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'where', {
  before-each {
    User.destroy-all;
  }

  after-each {
    User.destroy-all;
  }

  it 'creates a valid Fred', {
    my $fred = User.create({fname => 'Fred'});

    expect($fred.is-valid).to.be-truthy;
  }

  it 'creates a valid Barney', {
    my $barney = User.create({fname => 'Barney'});

    expect($barney.is-valid).to.be-truthy;
  }

  it 'counts both rows', {
    User.create({fname => 'Fred'});
    User.create({fname => 'Barney'});

    expect(User.count).to.eq(2);
  }

  it 'finds the matching row via where', {
    my $fred = User.create({fname => 'Fred'});
    User.create({fname => 'Barney'});

    my $result = User.where({fname => 'Fred'}).first;

    expect($result.id).to.eq($fred.id);
  }
}
