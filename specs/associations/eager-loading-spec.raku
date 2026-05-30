use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;
use Models::Profile;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

sub el-seed {
  clean-shared-tables;

  my %h;
  %h<alice> = User.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = User.create({fname => 'Bob',   lname => 'B'});

  Page.create({user => %h<alice>, name => 'Home'});
  Page.create({user => %h<alice>, name => 'About'});
  Page.create({user => %h<bob>,   name => 'Bio'});

  Profile.create({user => %h<alice>, bio => 'A bio'});
  Profile.create({user => %h<bob>,   bio => 'B bio'});

  Article.new(:id(0), :record({attrs => {title => 'A1', body => 'b', author_id => %h<alice>.id}})).save;
  Article.new(:id(0), :record({attrs => {title => 'A2', body => 'b', author_id => %h<alice>.id}})).save;
  Article.new(:id(0), :record({attrs => {title => 'B1', body => 'b', author_id => %h<bob>.id}})).save;
  %h;
}

describe 'eager loading', {
  before-each { el-seed }
  after-each  { clean-shared-tables }

  context 'preload has-many', {
    it 'loads parents', {
      my @users = User.where({}).preload(:pages).all;
      expect(@users.elems).to.eq(2);
    }

    it 'populates assoc-cache for has-many', {
      my @users = User.where({}).preload(:pages).all;
      expect(@users.first.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'returns preloaded pages through accessor', {
      my @users = User.where({}).preload(:pages).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pages.elems).to.eq(2);
    }
  }

  context 'preload has-one', {
    it 'populates assoc-cache for has-one', {
      my @users = User.where({}).preload(:profile).all;
      expect(@users.first.assoc-cache<profile>:exists).to.be-truthy;
    }

    it 'returns the correct child', {
      my @users = User.where({}).preload(:profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.profile.attrs<bio>).to.eq('A bio');
    }
  }

  context 'preload belongs-to with FK override', {
    it 'loads all articles', {
      my @articles = Article.where({}).preload(:scribe).all;
      expect(@articles.elems).to.eq(3);
    }

    it 'populates assoc-cache for belongs-to', {
      my @articles = Article.where({}).preload(:scribe).all;
      expect(@articles.first.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'returns the correct parent', {
      my @articles = Article.where({}).preload(:scribe).all;
      my $a1 = @articles.first({ .attrs<title> eq 'A1' });
      expect($a1.scribe.attrs<fname>).to.eq('Alice');
    }
  }

  it 'includes without references behaves like preload', {
    my @users = User.where({}).includes(:pages).all;
    expect(@users.first.assoc-cache<pages>:exists).to.be-truthy;
  }

  it 'eager-load populates the assoc-cache', {
    my @users = User.where({}).eager-load(:pages).all;
    expect(@users.first.assoc-cache<pages>:exists).to.be-truthy;
  }

  context 'nested preload via Pair', {
    it 'loads the top-level association', {
      my @users = User.where({}).preload(:pages, articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<articles>:exists).to.be-truthy;
    }

    it 'populates the child association', {
      my @users = User.where({}).preload(:pages, articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.articles;
      expect(@as.first.assoc-cache<scribe>:exists).to.be-truthy;
    }
  }

  context 'array form: multiple top-level names', {
    it 'loads first named association', {
      my @users = User.where({}).preload(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'loads second named association', {
      my @users = User.where({}).preload(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<profile>:exists).to.be-truthy;
    }

    it 'returns correct pages count', {
      my @users = User.where({}).preload(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pages.elems).to.eq(2);
    }

    it 'returns correct profile', {
      my @users = User.where({}).preload(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.profile.attrs<bio>).to.eq('A bio');
    }
  }

  context 'hash form: nested via Pair value', {
    it 'loads parent', {
      my @users = User.where({}).preload(articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<articles>:exists).to.be-truthy;
    }

    it 'loads child', {
      my @users = User.where({}).preload(articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.articles;
      expect(@as.first.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'child returns correct record', {
      my @users = User.where({}).preload(articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my @as = $alice-loaded.articles;
      expect(@as.first.scribe.attrs<fname>).to.eq('Alice');
    }
  }

  context 'deep nesting', {
    it 'scribe cached on article', {
      my @users = User.where({}).preload(articles => { scribe => :pages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.articles.first;
      expect($art.assoc-cache<scribe>:exists).to.be-truthy;
    }

    it 'pages cached on scribe', {
      my @users = User.where({}).preload(articles => { scribe => :pages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.articles.first;
      my $scribe = $art.scribe;
      expect($scribe.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'grandchild pages returned via cache', {
      my @users = User.where({}).preload(articles => { scribe => :pages }).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      my $art = $alice-loaded.articles.first;
      my $scribe = $art.scribe;
      expect($scribe.pages.elems).to.eq(2);
    }
  }

  context 'includes array form', {
    it 'loads pages', {
      my @users = User.where({}).includes(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'loads profile', {
      my @users = User.where({}).includes(:pages, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<profile>:exists).to.be-truthy;
    }
  }

  context 'includes hash form (nested)', {
    it 'loads parent', {
      my @users = User.where({}).includes(articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<articles>:exists).to.be-truthy;
    }

    it 'loads nested child', {
      my @users = User.where({}).includes(articles => :scribe).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.articles.first.assoc-cache<scribe>:exists).to.be-truthy;
    }
  }

  it 'eager-load top-level caches', {
    my @users = User.where({}).eager-load(:pages).all;
    expect(@users.first.assoc-cache<pages>:exists).to.be-truthy;
  }

  context 'eager-load + preload', {
    it 'top-level cached', {
      my @users = User.where({}).eager-load(:pages).preload(profile => True).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'secondary association cached', {
      my @users = User.where({}).eager-load(:pages).preload(profile => True).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<profile>:exists).to.be-truthy;
    }
  }

  context 'includes with references', {
    it 'caches first association', {
      my @users = User.where({}).references(:profile).includes(pages => True, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<pages>:exists).to.be-truthy;
    }

    it 'caches second association', {
      my @users = User.where({}).references(:profile).includes(pages => True, :profile).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.assoc-cache<profile>:exists).to.be-truthy;
    }
  }
}
