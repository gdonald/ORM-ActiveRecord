use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Article;
use Models::Passport;
use Models::Region;
use Models::Town;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'foreign-key and primary-key overrides', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'belongs-to with foreign-key override', {
    it 'saves the user', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'saves the article with author', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $article = Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect($article.is-valid).to.be-truthy;
    }

    it 'fills the override column', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $article = Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect($article.attrs<author_id>).to.eq($user.id);
    }

    it 'resolves the parent', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $article = Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(Article.find($article.id).author.defined).to.be-truthy;
    }

    it 'returns the right parent', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $article = Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(Article.find($article.id).author.id).to.eq($user.id);
    }
  }

  context 'has-many with foreign-key override', {
    it 'returns the matching row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(User.find($user.id).articles.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $article = Article.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(User.find($user.id).articles.first.id).to.eq($article.id);
    }
  }

  context 'has-one with foreign-key override', {
    it 'saves the passport', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $passport = Passport.create({owner => $user, number => 'AB12345'});
      expect($passport.is-valid).to.be-truthy;
    }

    it 'fills the override column', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $passport = Passport.create({owner => $user, number => 'AB12345'});
      expect($passport.attrs<owner_id>).to.eq($user.id);
    }

    it 'returns a defined row from has-one', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Passport.create({owner => $user, number => 'AB12345'});
      expect(User.find($user.id).passport.defined).to.be-truthy;
    }

    it 'returns the right row from has-one', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $passport = Passport.create({owner => $user, number => 'AB12345'});
      expect(User.find($user.id).passport.id).to.eq($passport.id);
    }

    it 'belongs-to back resolves user', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $passport = Passport.create({owner => $user, number => 'AB12345'});
      expect(Passport.find($passport.id).owner.defined).to.be-truthy;
    }

    it 'belongs-to back returns right user', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $passport = Passport.create({owner => $user, number => 'AB12345'});
      expect(Passport.find($passport.id).owner.id).to.eq($user.id);
    }
  }

  context 'primary-key override', {
    it 'saves the region', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      expect($usa.is-valid).to.be-truthy;
    }

    it 'saves the towns', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      my $dallas  = Town.create({region => $usa, name => 'Dallas'});
      my $austin  = Town.create({region => $usa, name => 'Austin'});
      expect($dallas.is-valid && $austin.is-valid).to.be-truthy;
    }

    it 'writes target pkey value into FK column', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      my $dallas = Town.create({region => $usa, name => 'Dallas'});
      expect($dallas.attrs<region_code>).to.eq('US');
    }

    it 'wires every town correctly', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      Town.create({region => $usa, name => 'Dallas'});
      my $austin = Town.create({region => $usa, name => 'Austin'});
      expect($austin.attrs<region_code>).to.eq('US');
    }

    it 'has-many resolves via override column', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      Town.create({region => $usa, name => 'Dallas'});
      Town.create({region => $usa, name => 'Austin'});
      expect(Region.find($usa.id).towns.elems).to.eq(2);
    }

    it 'has-many returns the right rows', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      Town.create({region => $usa, name => 'Dallas'});
      Town.create({region => $usa, name => 'Austin'});
      expect(Region.find($usa.id).towns.map(*.attrs<name>).sort.join(',')).to.eq('Austin,Dallas');
    }

    it 'belongs-to resolves the parent via override columns', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      my $dallas = Town.create({region => $usa, name => 'Dallas'});
      expect(Town.find($dallas.id).region.defined).to.be-truthy;
    }

    it 'belongs-to returns the right parent', {
      my $usa = Region.create({code => 'US', name => 'United States'});
      my $dallas = Town.create({region => $usa, name => 'Dallas'});
      expect(Town.find($dallas.id).region.attrs<code>).to.eq('US');
    }

    it 'returns no rows when no children match', {
      my $blank = Region.create({code => 'XX', name => 'Nowhere'});
      expect($blank.towns.elems).to.eq(0);
    }
  }
}
