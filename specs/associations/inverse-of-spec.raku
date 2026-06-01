use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;
use Models::Profile;
use Models::Article;
use Models::Employee;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'inverse-of', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:user, { User.new(:id(0)) });

  context 'auto-detected has-many → belongs-to', {
    let(:alice, { User.create({fname => 'Alice', lname => 'A'}) });

    context 'with two pages', {
      before-each { for <Home About> { Page.create(%(user => alice, name => $_)) } }

      it 'returns both pages', {
        expect(User.find(alice.id).pages.elems).to.eq(2);
      }

      it 'populates back-pointer on first child', {
        my $owner = User.find(alice.id);
        my @pages = $owner.pages;

        expect(@pages.first.user === $owner).to.be-truthy;
      }

      it 'populates back-pointer on every child', {
        my $owner = User.find(alice.id);
        my @pages = $owner.pages;

        expect(@pages[1].user === $owner).to.be-truthy;
      }
    }

    it 're-applies on re-access', {
      Page.create({user => alice, name => 'Home'});
      my $owner = User.find(alice.id);
      $owner.pages;
      my @pages-again = $owner.pages;

      expect(@pages-again.first.user === $owner).to.be-truthy;
    }
  }

  context 'auto-detected has-one → belongs-to', {
    let(:alice, { User.create({fname => 'Alice', lname => 'A'}) });
    let(:owner, { User.find(alice.id) });

    before-each { Profile.create({user => alice, bio => 'inverse-of test'}) }

    it 'returns a profile', {
      expect(owner.profile.defined).to.be-truthy;
    }

    it 'populates back-pointer on has-one', {
      expect(owner.profile.user).to.be(owner);
    }
  }

  context 'explicit inverse-of with foreign-key override', {
    let(:author,   { User.create({fname => 'Greg', lname => 'D'}) });
    let(:writer,   { User.find(author.id) });
    let(:articles, { writer.articles });

    before-each {
      for <Hi Yo> -> $title {
        Article.create({author => author, title => $title, body => 'world'});
      }
    }

    it 'returns rows', {
      expect(articles.elems).to.eq(2);
    }

    it 'populates back-pointer on first child', {
      expect(articles.first.scribe === writer).to.be-truthy;
    }

    it 'populates back-pointer on every child', {
      expect(articles[1].scribe === writer).to.be-truthy;
    }
  }

  context 'override without inverse-of disables auto-detection', {
    let(:spec, { %(class => Article, foreign-key => 'author_id') });

    it 'flags as disabled', {
      expect(user.assoc-auto-inverse-disabled(spec)).to.be-truthy;
    }

    it 'resolve-inverse-name returns empty', {
      expect(user.resolve-inverse-name(spec, Article)).to.eq('');
    }
  }

  context 'overrides without inverse-of, each access reloads independently', {
    let(:boss,        { Employee.create({name => 'Big'}) });
    let(:boss-loaded, { Employee.find(boss.id) });
    let(:subs,        { boss-loaded.subordinates });

    before-each { Employee.create({name => 'Min', manager => boss}) }

    it 'returns the row', {
      expect(subs.elems).to.eq(1);
    }

    it 'back-pointer is a fresh load', {
      expect(subs.first.manager === boss-loaded).to.be-falsy;
    }
  }

  context 'direct method coverage', {
    context 'articles has-many spec', {
      let(:art-spec, { user.has-manys<articles> });

      it 'explicit inverse-of wins even with overrides', {
        expect(user.resolve-inverse-name(art-spec, Article)).to.eq('scribe');
      }

      it 'assoc-inverse-name reads Pair-form as string', {
        expect(user.assoc-inverse-name(art-spec)).to.eq('scribe');
      }
    }

    it 'auto-detect picks single matching belongs-to', {
      my $page-spec = user.has-manys<pages>;
      expect(user.resolve-inverse-name($page-spec, Page)).to.eq('user');
    }

    it 'assoc-inverse-name accepts plain string', {
      my $str-spec = %(class => Article, inverse-of => 'scribe');
      expect(user.assoc-inverse-name($str-spec)).to.eq('scribe');
    }
  }
}
