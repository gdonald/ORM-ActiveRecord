use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class WhUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
  }
}

describe 'where', {
  before-each {
    WhUser.destroy-all;
  }

  after-each {
    WhUser.destroy-all;
  }

  it 'creates a valid Fred', {
    my $fred = WhUser.create({fname => 'Fred'});

    expect($fred.is-valid).to.be-truthy;
  }

  it 'creates a valid Barney', {
    my $barney = WhUser.create({fname => 'Barney'});

    expect($barney.is-valid).to.be-truthy;
  }

  it 'counts both rows', {
    WhUser.create({fname => 'Fred'});
    WhUser.create({fname => 'Barney'});

    expect(WhUser.count).to.eq(2);
  }

  it 'finds the matching row via where', {
    my $fred = WhUser.create({fname => 'Fred'});
    WhUser.create({fname => 'Barney'});

    my $result = WhUser.where({fname => 'Fred'}).first;

    expect($result.id).to.eq($fred.id);
  }
}
