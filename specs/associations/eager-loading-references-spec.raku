use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;
use Models::Profile;

%*ENV<DISABLE-SQL-LOG> = True;

sub elr-seed {
  clean-shared-tables;

  my $alice = User.create({fname => 'Alice', lname => 'A'});
  my $bob   = User.create({fname => 'Bob',   lname => 'B'});

  Page.create({user => $alice, name => 'A1'});
  Page.create({user => $alice, name => 'A2'});
  Page.create({user => $bob,   name => 'B1'});

  Profile.create({user => $alice, bio => 'alice bio'});
  Profile.create({user => $bob,   bio => 'bob bio'});
}

describe 'eager loading references', {
  before-each { elr-seed }
  after-each  { clean-shared-tables }

  context 'references after includes promotes to eager-load', {
    it 'JOIN appears in SQL', {
      my $q = User.where({}).includes(:profile).references(:profile);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'cache populated', {
      my @users = User.where({}).includes(:profile).references(:profile).all;
      expect(@users.first.assoc-cache<profile>:exists).to.be-truthy;
    }
  }

  context 'order does not matter', {
    it 'JOIN appears in SQL', {
      my $q = User.where({}).references(:profile).includes(:profile);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'cache populated', {
      my @users = User.where({}).references(:profile).includes(:profile).all;
      expect(@users.first.assoc-cache<profile>:exists).to.be-truthy;
    }
  }

  context 'Pair form references(assoc => Bool)', {
    it 'promotes includes when the Pair value is true', {
      my $q = User.where({}).includes(:profile).references(profile => True);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'does not promote when the Pair value is false', {
      my $q = User.where({}).includes(:profile).references(profile => False);
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
    }
  }

  it 'includes alone (no references) stays as preload', {
    my $sql = User.where({}).includes(:profile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }

  it 'explicit preload is not promoted by references', {
    my $sql = User.where({}).preload(:profile).references(:profile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }

  context 'auto-references via dotted where key', {
    it 'promotes includes', {
      my $q = User.where({}).includes(:profile).where({'profiles.bio' => 'alice bio'});
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'query filters correctly', {
      my @users = User.where({}).includes(:profile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.elems).to.eq(1);
    }

    it 'returns the right row', {
      my @users = User.where({}).includes(:profile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.first.attrs<fname>).to.eq('Alice');
    }

    it 'still caches the association', {
      my @users = User.where({}).includes(:profile).where({'profiles.bio' => 'alice bio'}).all;
      expect(@users.first.assoc-cache<profile>:exists).to.be-truthy;
    }
  }

  context 'auto-references via nested-hash where form', {
    it 'promotes includes', {
      my $q = User.where({}).includes(:profile).where({profiles => {bio => 'bob bio'}});
      expect($q.to-sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
    }

    it 'filters correctly', {
      my @users = User.where({}).includes(:profile).where({profiles => {bio => 'bob bio'}}).all;
      expect(@users.first.attrs<fname>).to.eq('Bob');
    }
  }

  it 'auto-references via order on joined table', {
    my $sql = User.where({}).includes(:profile).order('profiles.bio DESC').to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-truthy;
  }

  it 'where filtering on base table does not promote', {
    my $sql = User.where({fname => 'Alice'}).includes(:profile).to-sql;
    expect($sql.contains('LEFT OUTER JOIN profiles')).to.be-falsy;
  }
}
