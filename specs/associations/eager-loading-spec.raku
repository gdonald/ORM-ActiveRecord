use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class ElPage    {...}
class ElProfile {...}
class ElArticle {...}

class ElUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: elpages    => %(class => ElPage,    foreign-key => 'user_id');
    self.has-one:  elprofile  => %(class => ElProfile, foreign-key => 'user_id');
    self.has-many: elarticles => %(
      class       => ElArticle,
      foreign-key => 'author_id',
      inverse-of  => :scribe,
    );
  }
}

class ElPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: eluser => %(class => ElUser, foreign-key => 'user_id');
  }
}

class ElProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: eluser => %(class => ElUser, foreign-key => 'user_id');
  }
}

class ElArticle is Model {
  method table-name { 'articles' }

  submethod BUILD {
    self.belongs-to: scribe => %(class => ElUser, foreign-key => 'author_id');
  }
}

sub el-seed {
  clean-shared-tables;

  my %h;
  %h<alice> = ElUser.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = ElUser.create({fname => 'Bob',   lname => 'B'});

  ElPage.create({eluser => %h<alice>, name => 'Home'});
  ElPage.create({eluser => %h<alice>, name => 'About'});
  ElPage.create({eluser => %h<bob>,   name => 'Bio'});

  ElProfile.create({eluser => %h<alice>, bio => 'A bio'});
  ElProfile.create({eluser => %h<bob>,   bio => 'B bio'});

  ElArticle.new(:id(0), :record({attrs => {title => 'A1', body => 'b', author_id => %h<alice>.id}})).save;
  ElArticle.new(:id(0), :record({attrs => {title => 'A2', body => 'b', author_id => %h<alice>.id}})).save;
  ElArticle.new(:id(0), :record({attrs => {title => 'B1', body => 'b', author_id => %h<bob>.id}})).save;
  %h;
}

sub el-clean {
  clean-shared-tables;
}

describe 'eager loading', {
  before-each { el-seed }
  after-each  { el-clean }

  context 'preload has-many', {
    it 'loads parents', {
      my @users = ElUser.where({}).preload(:elpages).all;
      expect(@users.elems).to.eq(2);
    }

    it 'populates assoc-cache for has-many', {
      my @users = ElUser.where({}).preload(:elpages).all;
      expect(@users.first.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'returns preloaded pages through accessor', {
      my @users = ElUser.where({}).preload(:elpages).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.elpages.elems).to.eq(2);
    }
  }

  context 'preload has-one', {
    it 'populates assoc-cache for has-one', {
      my @users = ElUser.where({}).preload(:elprofile).all;
      expect(@users.first.assoc-cache<elprofile>:exists).to.be-truthy;
    }

    it 'returns the correct child', {
      my @users = ElUser.where({}).preload(:elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.elprofile.attrs<bio>).to.eq('A bio');
    }
  }

  context 'preload belongs-to with FK override', {
    it 'loads all articles', {
      my @articles = ElArticle.where({}).preload(:scribe).all;
      expect(@articles.elems).to.eq(3);
    }

    it 'populates assoc-cache for belongs-to', {
      my @articles = ElArticle.where({}).preload(:scribe).all;
      expect(@articles.first.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'returns the correct parent', {
      my @articles = ElArticle.where({}).preload(:scribe).all;
      my $a1 = @articles.first({ .attrs<title> eq 'A1' });
      expect($a1.scribe.attrs<fname>).to.eq('Alice');
    }
  }

  it 'includes without references behaves like preload', {
    my @users = ElUser.where({}).includes(:elpages).all;
    expect(@users.first.assoc-cache<elpages>:exists).to.be-truthy;
  }

  it 'eager-load populates the assoc-cache', {
    my @users = ElUser.where({}).eager-load(:elpages).all;
    expect(@users.first.assoc-cache<elpages>:exists).to.be-truthy;
  }

  context 'nested preload via Pair', {
    it 'loads the top-level association', {
      my @users = ElUser.where({}).preload(:elpages, elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elarticles>:exists).to.be-truthy;
    }

    it 'populates the child association', {
      my @users = ElUser.where({}).preload(:elpages, elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.elarticles;
      expect(@as.first.assoc-cache<scribe>:exists).to.be-truthy;
    }
  }

  context 'array form: multiple top-level names', {
    it 'loads first named association', {
      my @users = ElUser.where({}).preload(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'loads second named association', {
      my @users = ElUser.where({}).preload(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elprofile>:exists).to.be-truthy;
    }

    it 'returns correct pages count', {
      my @users = ElUser.where({}).preload(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.elpages.elems).to.eq(2);
    }

    it 'returns correct profile', {
      my @users = ElUser.where({}).preload(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.elprofile.attrs<bio>).to.eq('A bio');
    }
  }

  context 'hash form: nested via Pair value', {
    it 'loads parent', {
      my @users = ElUser.where({}).preload(elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elarticles>:exists).to.be-truthy;
    }

    it 'loads child', {
      my @users = ElUser.where({}).preload(elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.elarticles;
      expect(@as.first.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'child returns correct record', {
      my @users = ElUser.where({}).preload(elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.elarticles;
      expect(@as.first.scribe.attrs<fname>).to.eq('Alice');
    }
  }

  context 'deep nesting', {
    it 'scribe cached on article', {
      my @users = ElUser.where({}).preload(elarticles => { scribe => :elpages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.elarticles.first;
      expect($art.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'pages cached on scribe', {
      my @users = ElUser.where({}).preload(elarticles => { scribe => :elpages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.elarticles.first;
      my $scribe = $art.scribe;
      expect($scribe.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'grandchild pages returned via cache', {
      my @users = ElUser.where({}).preload(elarticles => { scribe => :elpages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.elarticles.first;
      my $scribe = $art.scribe;
      expect($scribe.elpages.elems).to.eq(2);
    }
  }

  context 'includes array form', {
    it 'loads pages', {
      my @users = ElUser.where({}).includes(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'loads profile', {
      my @users = ElUser.where({}).includes(:elpages, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elprofile>:exists).to.be-truthy;
    }
  }

  context 'includes hash form (nested)', {
    it 'loads parent', {
      my @users = ElUser.where({}).includes(elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elarticles>:exists).to.be-truthy;
    }

    it 'loads nested child', {
      my @users = ElUser.where({}).includes(elarticles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.elarticles.first.assoc-cache<scribe>:exists).to.be-truthy;
    }
  }

  it 'eager-load top-level caches', {
    my @users = ElUser.where({}).eager-load(:elpages).all;
    expect(@users.first.assoc-cache<elpages>:exists).to.be-truthy;
  }

  context 'eager-load + preload', {
    it 'top-level cached', {
      my @users = ElUser.where({}).eager-load(:elpages).preload(elprofile => True).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'secondary association cached', {
      my @users = ElUser.where({}).eager-load(:elpages).preload(elprofile => True).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elprofile>:exists).to.be-truthy;
    }
  }

  context 'includes with references', {
    it 'caches first association', {
      my @users = ElUser.where({}).references(:elprofile).includes(elpages => True, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elpages>:exists).to.be-truthy;
    }

    it 'caches second association', {
      my @users = ElUser.where({}).references(:elprofile).includes(elpages => True, :elprofile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<elprofile>:exists).to.be-truthy;
    }
  }
}
