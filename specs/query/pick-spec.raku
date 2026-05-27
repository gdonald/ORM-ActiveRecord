use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PkUser is Model {
  method table-name { 'users' }
}

describe 'pick', {
  before-each {
    PkUser.destroy-all;
    PkUser.create({fname => 'Alice', lname => 'Aardvark'});
    PkUser.create({fname => 'Bob',   lname => 'Bear'});
    PkUser.create({fname => 'Carol', lname => 'Cat'});
  }

  after-each {
    PkUser.destroy-all;
  }

  it 'pick(col) returns scalar from first matched row', {
    my $first-fname = PkUser.order('fname').pick('fname');

    expect($first-fname).to.eq('Alice');
  }

  it 'pick respects where', {
    my $bob = PkUser.where({fname => 'Bob'}).pick('lname');

    expect($bob).to.eq('Bear');
  }

  it 'pick(a,b) returns list', {
    my $row = PkUser.order('fname').pick('fname', 'lname');

    expect($row.defined && $row.elems == 2 && $row[0] eq 'Alice' && $row[1] eq 'Aardvark').to.be-truthy;
  }

  it 'pick on no rows returns Any', {
    my $none = PkUser.where({fname => 'Zelda'}).pick('fname');

    expect($none.defined).to.be-falsy;
  }

  it 'Model.pick(col) works at the class level', {
    my $any-fname = PkUser.pick('fname');

    expect($any-fname.defined).to.be-truthy;
  }

  it 'pick on .none returns Any without hitting DB', {
    my $none-pick = PkUser.none.pick('fname');

    expect($none-pick.defined).to.be-falsy;
  }

  it 'pick does not permanently set limit on the relation', {
    my $q = PkUser.order('fname');
    $q.pick('fname');

    expect($q.all.elems).to.eq(3);
  }
}
