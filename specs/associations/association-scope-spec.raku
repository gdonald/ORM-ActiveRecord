use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Relation::Query;
use Models::User;
use Models::Article;
use Models::Profile;
use Models::Tag;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'association scope', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'block scope on has-many filters by where', {
    it 'returns only published rows', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True,  active-author => $alice});
      Article.create({title => 'mid',  score => 5, published => True,  active-author => $alice});
      Article.create({title => 'high', score => 9, published => True,  active-author => $alice});
      Article.create({title => 'wip',  score => 2, published => False, active-author => $alice});

      expect($alice.published-articles.elems).to.eq(3);
    }

    it 'excludes drafts', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True,  active-author => $alice});
      my $draft = Article.create({title => 'wip', score => 2, published => False, active-author => $alice});

      expect($alice.published-articles.map({ .id }).Bag{$draft.id}:!exists).to.be-truthy;
    }
  }

  context 'scope with limit', {
    it 'returns two records', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True, active-author => $alice});
      Article.create({title => 'mid',  score => 5, published => True, active-author => $alice});
      Article.create({title => 'high', score => 9, published => True, active-author => $alice});

      expect($alice.top-articles.elems).to.eq(2);
    }

    it 'orders by score ASC then limits', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True, active-author => $alice});
      Article.create({title => 'mid',  score => 5, published => True, active-author => $alice});
      Article.create({title => 'high', score => 9, published => True, active-author => $alice});

      expect($alice.top-articles.map({ .attrs<title> }).join(',')).to.eq('low,mid');
    }
  }

  context 'argument-taking scope', {
    it 'filters with caller-supplied bound', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True, active-author => $alice});
      Article.create({title => 'mid',  score => 5, published => True, active-author => $alice});
      Article.create({title => 'high', score => 9, published => True, active-author => $alice});

      expect($alice.by-score(5).map({ .attrs<title> }).sort.join(',')).to.eq('high,mid');
    }

    it 'reflects different bound', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      Article.create({title => 'low',  score => 1, published => True, active-author => $alice});
      Article.create({title => 'mid',  score => 5, published => True, active-author => $alice});
      Article.create({title => 'high', score => 9, published => True, active-author => $alice});

      expect($alice.by-score(9).map({ .attrs<title> }).join(',')).to.eq('high');
    }
  }

  it 'has-one scope filters by visible', {
    my $alice = User.create({fname => 'Alice', is_active => True});
    my $visible-prof = Profile.create({bio => 'pinned', visible => True, user => $alice});
    Profile.create({bio => 'hidden', visible => False, user => $alice});

    expect(User.find($alice.id).visible-profile.id).to.eq($visible-prof.id);
  }

  context 'belongs-to scope', {
    it 'hides article whose author is inactive', {
      my $inactive = User.create({fname => 'Zed', is_active => False});
      my $orphan = Article.create({title => 'orphan', published => True, score => 0, active-author => $inactive});

      expect(Article.find($orphan.id).active-author.defined).to.be-falsy;
    }

    it 'still returns active author', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      my $pub-low = Article.create({title => 'low', score => 1, published => True, active-author => $alice});

      expect(Article.find($pub-low.id).active-author.defined).to.be-truthy;
    }
  }

  context 'habtm scope', {
    it 'filters out non-hot rows', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      my $pub-low = Article.create({title => 'low', score => 1, published => True, active-author => $alice});
      my $hot  = Tag.create({name => 'raku', hot => True});
      my $cool = Tag.create({name => 'old',  hot => False});
      $pub-low.add-hot-tag($hot);
      $pub-low.add-hot-tag($cool);

      expect(Article.find($pub-low.id).hot-tags.elems).to.eq(1);
    }

    it 'returns matching row', {
      my $alice = User.create({fname => 'Alice', is_active => True});
      my $pub-low = Article.create({title => 'low', score => 1, published => True, active-author => $alice});
      my $hot  = Tag.create({name => 'raku', hot => True});
      my $cool = Tag.create({name => 'old',  hot => False});
      $pub-low.add-hot-tag($hot);
      $pub-low.add-hot-tag($cool);

      expect(Article.find($pub-low.id).hot-tags.first.attrs<name>).to.eq('raku');
    }
  }
}
