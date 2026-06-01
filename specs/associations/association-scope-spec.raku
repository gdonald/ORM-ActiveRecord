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

  let(:alice, { User.create({fname => 'Alice', is_active => True}) });

  context 'with published articles scored 1, 5, and 9', {
    before-each {
      Article.create({title => 'low',  score => 1, published => True, active-author => alice});
      Article.create({title => 'mid',  score => 5, published => True, active-author => alice});
      Article.create({title => 'high', score => 9, published => True, active-author => alice});
    }

    context 'has-many block scope filters by where', {
      let-bang(:draft, { Article.create({title => 'wip', score => 2, published => False, active-author => alice}) });

      it 'returns only the published rows', {
        expect(alice.published-articles.elems).to.eq(3);
      }

      it 'excludes the draft', {
        expect(alice.published-articles.map({ .id }).Bag{draft.id}:!exists).to.be-truthy;
      }
    }

    context 'has-many scope with a limit', {
      it 'returns two records', {
        expect(alice.top-articles.elems).to.eq(2);
      }

      it 'orders by score ascending before limiting', {
        expect(alice.top-articles.map({ .attrs<title> }).join(',')).to.eq('low,mid');
      }
    }

    context 'has-many scope taking an argument', {
      it 'filters by the caller-supplied bound', {
        expect(alice.by-score(5).map({ .attrs<title> }).sort.join(',')).to.eq('high,mid');
      }

      it 'reflects a different bound', {
        expect(alice.by-score(9).map({ .attrs<title> }).join(',')).to.eq('high');
      }
    }
  }

  it 'has-one scope returns only the visible profile', {
    my $visible-prof = Profile.create({bio => 'pinned', visible => True, user => alice});
    Profile.create({bio => 'hidden', visible => False, user => alice});

    expect(User.find(alice.id).visible-profile.id).to.eq($visible-prof.id);
  }

  context 'belongs-to scope', {
    it 'hides an article whose author is inactive', {
      my $inactive = User.create({fname => 'Zed', is_active => False});
      my $orphan = Article.create({title => 'orphan', published => True, score => 0, active-author => $inactive});

      expect(Article.find($orphan.id).active-author.defined).to.be-falsy;
    }

    it 'returns an active author', {
      my $pub-low = Article.create({title => 'low', score => 1, published => True, active-author => alice});

      expect(Article.find($pub-low.id).active-author.defined).to.be-truthy;
    }
  }

  context 'has-and-belongs-to-many scope', {
    let(:pub-low,  { Article.create({title => 'low', score => 1, published => True, active-author => alice}) });
    let(:hot-tags, { Article.find(pub-low.id).hot-tags });

    before-each {
      pub-low.add-hot-tag(Tag.create({name => 'raku', hot => True}));
      pub-low.add-hot-tag(Tag.create({name => 'old',  hot => False}));
    }

    it 'excludes the non-hot tag', {
      expect(hot-tags.elems).to.eq(1);
    }

    it 'returns the hot tag', {
      expect(hot-tags.first.attrs<name>).to.eq('raku');
    }
  }
}
