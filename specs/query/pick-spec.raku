use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'pick', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Aardvark'});
    User.create({fname => 'Bob',   lname => 'Bear'});
    User.create({fname => 'Carol', lname => 'Cat'});
  }

  after-each {
    User.destroy-all;
  }

  it 'pick(col) returns scalar from first matched row', {
    my $first-fname = User.order('fname').pick('fname');

    expect($first-fname).to.eq('Alice');
  }

  it 'pick respects where', {
    my $bob = User.where({fname => 'Bob'}).pick('lname');

    expect($bob).to.eq('Bear');
  }

  it 'pick(a,b) returns list', {
    my $row = User.order('fname').pick('fname', 'lname');

    expect($row.defined && $row.elems == 2 && $row[0] eq 'Alice' && $row[1] eq 'Aardvark').to.be-truthy;
  }

  it 'pick on no rows returns Any', {
    my $none = User.where({fname => 'Zelda'}).pick('fname');

    expect($none.defined).to.be-falsy;
  }

  it 'Model.pick(col) works at the class level', {
    my $any-fname = User.pick('fname');

    expect($any-fname.defined).to.be-truthy;
  }

  it 'pick on .none returns Any without hitting DB', {
    my $none-pick = User.none.pick('fname');

    expect($none-pick.defined).to.be-falsy;
  }

  it 'pick does not permanently set limit on the relation', {
    my $q = User.order('fname');
    $q.pick('fname');

    expect($q.all.elems).to.eq(3);
  }
}
