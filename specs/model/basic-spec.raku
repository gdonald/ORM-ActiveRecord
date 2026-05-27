use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BaPage {...}

class BaUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: pages => %(class => BaPage, foreign-key => 'user_id');

    self.validate: 'fname', { :presence, length => { min => 4, max => 32 } }
    self.validate: 'lname', { :presence, length => { min => 4, max => 32 } }
  }

  method fullname {
    self.fname ~ ' ' ~ self.lname;
  }
}

class BaPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: user => %(class => BaUser, foreign-key => 'user_id');

    self.validate: 'name', { :presence, length => { min => 4, max => 32 } }
  }
}

describe 'a basic Model', {
  before-each {
    BaPage.destroy-all;
    BaUser.destroy-all;
  }

  after-each {
    BaPage.destroy-all;
    BaUser.destroy-all;
  }

  it 'creates a row and assigns an id', {
    my $user = BaUser.create({fname => 'Greg', lname => 'Donald'});
    expect($user.id).to.be-greater-than(0);
  }

  it 'reads back attributes through has-many / belongs-to', {
    my $user = BaUser.create({fname => 'Greg', lname => 'Donald'});
    BaPage.create({:$user, name => 'Raku'});
    my $page = $user.pages.first;

    expect($page.name).to.eq('Raku');
    expect($page.user.fullname).to.eq('Greg Donald');
  }

  it 'reassigns belongs-to via update', {
    my $user = BaUser.create({fname => 'Greg', lname => 'Donald'});
    BaPage.create({:$user, name => 'Raku'});
    my $page = $user.pages.first;

    my $alfred = BaUser.create({fname => 'Alfred E.', lname => 'Neuman'});
    $page.update({user => $alfred});

    expect($page.user.fullname).to.eq('Alfred E. Neuman');
  }
}
