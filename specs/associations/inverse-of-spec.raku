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

  context 'auto-detected has-many → belongs-to', {
    it 'returns both pages', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Page.create({user => $u-seed, name => 'Home'});
      Page.create({user => $u-seed, name => 'About'});

      expect(User.find($u-seed.id).pages.elems).to.eq(2);
    }

    it 'populates back-pointer on first child', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Page.create({user => $u-seed, name => 'Home'});
      Page.create({user => $u-seed, name => 'About'});
      my $owner = User.find($u-seed.id);
      my @pages = $owner.pages;

      expect(@pages.first.user === $owner).to.be-truthy;
    }

    it 'populates back-pointer on every child', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Page.create({user => $u-seed, name => 'Home'});
      Page.create({user => $u-seed, name => 'About'});
      my $owner = User.find($u-seed.id);
      my @pages = $owner.pages;

      expect(@pages[1].user === $owner).to.be-truthy;
    }

    it 're-applies on re-access', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Page.create({user => $u-seed, name => 'Home'});
      my $owner = User.find($u-seed.id);
      $owner.pages;
      my @pages-again = $owner.pages;

      expect(@pages-again.first.user === $owner).to.be-truthy;
    }
  }

  context 'auto-detected has-one → belongs-to', {
    it 'returns a profile', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Profile.create({user => $u-seed, bio => 'inverse-of test'});
      my $owner2 = User.find($u-seed.id);

      expect($owner2.profile.defined).to.be-truthy;
    }

    it 'populates back-pointer on has-one', {
      my $u-seed = User.create({fname => 'Alice', lname => 'A'});
      Profile.create({user => $u-seed, bio => 'inverse-of test'});
      my $owner2 = User.find($u-seed.id);
      my $prof = $owner2.profile;

      expect($prof.user === $owner2).to.be-truthy;
    }
  }

  context 'explicit inverse-of with foreign-key override', {
    it 'returns rows', {
      my $author = User.create({fname => 'Greg', lname => 'D'});
      Article.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      Article.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = User.find($author.id);

      expect($writer.articles.elems).to.eq(2);
    }

    it 'populates back-pointer on first child', {
      my $author = User.create({fname => 'Greg', lname => 'D'});
      Article.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      Article.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = User.find($author.id);
      my @articles = $writer.articles;

      expect(@articles.first.scribe === $writer).to.be-truthy;
    }

    it 'populates back-pointer on every child', {
      my $author = User.create({fname => 'Greg', lname => 'D'});
      Article.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      Article.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = User.find($author.id);
      my @articles = $writer.articles;

      expect(@articles[1].scribe === $writer).to.be-truthy;
    }
  }

  context 'override without inverse-of disables auto-detection', {
    it 'flags as disabled', {
      my $spec = %(class => Article, foreign-key => 'author_id');
      expect(User.new(:id(0)).assoc-auto-inverse-disabled($spec)).to.be-truthy;
    }

    it 'resolve-inverse-name returns empty', {
      my $spec = %(class => Article, foreign-key => 'author_id');
      expect(User.new(:id(0)).resolve-inverse-name($spec, Article)).to.eq('');
    }
  }

  context 'overrides without inverse-of, each access reloads independently', {
    it 'returns the row', {
      my $boss = Employee.create({name => 'Big'});
      Employee.create({name => 'Min', manager => $boss});
      my $boss-loaded = Employee.find($boss.id);
      my @subs = $boss-loaded.subordinates;

      expect(@subs.elems).to.eq(1);
    }

    it 'back-pointer is a fresh load', {
      my $boss = Employee.create({name => 'Big'});
      Employee.create({name => 'Min', manager => $boss});
      my $boss-loaded = Employee.find($boss.id);
      my @subs = $boss-loaded.subordinates;

      expect(@subs.first.manager === $boss-loaded).to.be-falsy;
    }
  }

  context 'direct method coverage', {
    it 'auto-detect picks single matching belongs-to', {
      my $page-spec = User.new(:id(0)).has-manys<pages>;
      expect(User.new(:id(0)).resolve-inverse-name($page-spec, Page)).to.eq('user');
    }

    it 'explicit inverse-of wins even with overrides', {
      my $art-spec = User.new(:id(0)).has-manys<articles>;
      expect(User.new(:id(0)).resolve-inverse-name($art-spec, Article)).to.eq('scribe');
    }

    it 'assoc-inverse-name reads Pair-form as string', {
      my $art-spec = User.new(:id(0)).has-manys<articles>;
      expect(User.new(:id(0)).assoc-inverse-name($art-spec)).to.eq('scribe');
    }

    it 'assoc-inverse-name accepts plain string', {
      my $str-spec = %(class => Article, inverse-of => 'scribe');
      expect(User.new(:id(0)).assoc-inverse-name($str-spec)).to.eq('scribe');
    }
  }
}
