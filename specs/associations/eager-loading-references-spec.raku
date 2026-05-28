use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class ElrPage    {...}
class ElrProfile {...}

class ElrUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: elrpages   => %(class => ElrPage,    foreign-key => 'user_id');
    self.has-one:  elrprofile => %(class => ElrProfile, foreign-key => 'user_id');
  }
}

class ElrPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: elruser => %(class => ElrUser, foreign-key => 'user_id');
  }
}

class ElrProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: elruser => %(class => ElrUser, foreign-key => 'user_id');
  }
}

sub elr-seed {
  clean-shared-tables;

  my $alice = ElrUser.create({fname => 'Alice', lname => 'A'});
  my $bob   = ElrUser.create({fname => 'Bob',   lname => 'B'});

  ElrPage.create({elruser => $alice, name => 'A1'});
  ElrPage.create({elruser => $alice, name => 'A2'});
  ElrPage.create({elruser => $bob,   name => 'B1'});

  ElrProfile.create({elruser => $alice, bio => 'alice bio'});
  ElrProfile.create({elruser => $bob,   bio => 'bob bio'});
}

sub elr-clean {
  clean-shared-tables;
}

describe 'eager loading references', {
  before-each { elr-seed }
  after-each  { elr-clean }

  context 'references after includes promotes to eager-load', {
    it 'JOIN appears in SQL', {
      my $q = ElrUser.where({}).includes(:elrprofile).references(:elrprofile);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'cache populated', {
      my @users = ElrUser.where({}).includes(:elrprofile).references(:elrprofile).all;
      expect(@users.first.assoc-cache<elrprofile>:exists).to.be-truthy;
    }
  }

  context 'order does not matter', {
    it 'JOIN appears in SQL', {
      my $q = ElrUser.where({}).references(:elrprofile).includes(:elrprofile);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'cache populated', {
      my @users = ElrUser.where({}).references(:elrprofile).includes(:elrprofile).all;
      expect(@users.first.assoc-cache<elrprofile>:exists).to.be-truthy;
    }
  }

  context 'Pair form references(assoc => Bool)', {
    it 'promotes includes when the Pair value is true', {
      my $q = ElrUser.where({}).includes(:elrprofile).references(elrprofile => True);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'does not promote when the Pair value is false', {
      my $q = ElrUser.where({}).includes(:elrprofile).references(elrprofile => False);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
    }
  }

  it 'includes alone (no references) stays as preload', {
    my $sql = ElrUser.where({}).includes(:elrprofile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }

  it 'explicit preload is not promoted by references', {
    my $sql = ElrUser.where({}).preload(:elrprofile).references(:elrprofile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }

  context 'auto-references via dotted where key', {
    it 'promotes includes', {
      my $q = ElrUser.where({}).includes(:elrprofile).where({'profiles.bio' => 'alice bio'});
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'query filters correctly', {
      my @users = ElrUser.where({}).includes(:elrprofile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.elems).to.eq(1);
    }

    it 'returns the right row', {
      my @users = ElrUser.where({}).includes(:elrprofile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.first.attrs<fname>).to.eq('Alice');
    }

    it 'still caches the association', {
      my @users = ElrUser.where({}).includes(:elrprofile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.first.assoc-cache<elrprofile>:exists).to.be-truthy;
    }
  }

  context 'auto-references via nested-hash where form', {
    it 'promotes includes', {
      my $q = ElrUser.where({}).includes(:elrprofile).where({profiles => {bio => 'bob bio'}});
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'filters correctly', {
      my @users = ElrUser.where({}).includes(:elrprofile).where({profiles => {bio => 'bob bio'}}).all;
      expect(@users.first.attrs<fname>).to.eq('Bob');
    }
  }

  it 'auto-references via order on joined table', {
    my $sql = ElrUser.where({}).includes(:elrprofile).order('profiles.bio DESC').to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
  }

  it 'where filtering on base table does not promote', {
    my $sql = ElrUser.where({fname => 'Alice'}).includes(:elrprofile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }
}
