use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class FpkArticle  {...}
class FpkPassport {...}
class FpkTown     {...}

class FpkUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: fpkarticles => %(class => FpkArticle,  foreign-key => 'author_id');
    self.has-one:  fpkpassport => %(class => FpkPassport, foreign-key => 'owner_id');
  }
}

class FpkArticle is Model {
  method table-name { 'articles' }
  method fkey-name  { 'article_id' }

  submethod BUILD {
    self.belongs-to: author => %(class => FpkUser, foreign-key => 'author_id');
  }
}

class FpkPassport is Model {
  method table-name { 'passports' }

  submethod BUILD {
    self.belongs-to: owner => %(class => FpkUser, foreign-key => 'owner_id');
  }
}

class FpkRegion is Model {
  method table-name { 'regions' }
  method fkey-name  { 'region_id' }

  submethod BUILD {
    self.has-many: fpktowns => %(class => FpkTown, primary-key => 'code', foreign-key => 'region_code');
  }
}

class FpkTown is Model {
  method table-name { 'towns' }

  submethod BUILD {
    self.belongs-to: region => %(class => FpkRegion, primary-key => 'code', foreign-key => 'region_code');
  }
}

describe 'foreign-key and primary-key overrides', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'belongs-to with foreign-key override', {
    it 'saves the user', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'saves the article with author', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $article = FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect($article.is-valid).to.be-truthy;
    }

    it 'fills the override column', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $article = FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect($article.attrs<author_id>).to.eq($user.id);
    }

    it 'resolves the parent', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $article = FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(FpkArticle.find($article.id).author.defined).to.be-truthy;
    }

    it 'returns the right parent', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $article = FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(FpkArticle.find($article.id).author.id).to.eq($user.id);
    }
  }

  context 'has-many with foreign-key override', {
    it 'returns the matching row', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(FpkUser.find($user.id).fpkarticles.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $article = FpkArticle.create({title => 'Raku ORM', body => 'A library.', author => $user});
      expect(FpkUser.find($user.id).fpkarticles.first.id).to.eq($article.id);
    }
  }

  context 'has-one with foreign-key override', {
    it 'saves the passport', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $passport = FpkPassport.create({owner => $user, number => 'AB12345'});
      expect($passport.is-valid).to.be-truthy;
    }

    it 'fills the override column', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $passport = FpkPassport.create({owner => $user, number => 'AB12345'});
      expect($passport.attrs<owner_id>).to.eq($user.id);
    }

    it 'returns a defined row from has-one', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      FpkPassport.create({owner => $user, number => 'AB12345'});
      expect(FpkUser.find($user.id).fpkpassport.defined).to.be-truthy;
    }

    it 'returns the right row from has-one', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $passport = FpkPassport.create({owner => $user, number => 'AB12345'});
      expect(FpkUser.find($user.id).fpkpassport.id).to.eq($passport.id);
    }

    it 'belongs-to back resolves user', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $passport = FpkPassport.create({owner => $user, number => 'AB12345'});
      expect(FpkPassport.find($passport.id).owner.defined).to.be-truthy;
    }

    it 'belongs-to back returns right user', {
      my $user = FpkUser.create({fname => 'Greg', lname => 'Donald'});
      my $passport = FpkPassport.create({owner => $user, number => 'AB12345'});
      expect(FpkPassport.find($passport.id).owner.id).to.eq($user.id);
    }
  }

  context 'primary-key override', {
    it 'saves the region', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      expect($usa.is-valid).to.be-truthy;
    }

    it 'saves the towns', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      my $dallas  = FpkTown.create({region => $usa, name => 'Dallas'});
      my $austin  = FpkTown.create({region => $usa, name => 'Austin'});
      expect($dallas.is-valid && $austin.is-valid).to.be-truthy;
    }

    it 'writes target pkey value into FK column', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      my $dallas = FpkTown.create({region => $usa, name => 'Dallas'});
      expect($dallas.attrs<region_code>).to.eq('US');
    }

    it 'wires every town correctly', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      FpkTown.create({region => $usa, name => 'Dallas'});
      my $austin = FpkTown.create({region => $usa, name => 'Austin'});
      expect($austin.attrs<region_code>).to.eq('US');
    }

    it 'has-many resolves via override column', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      FpkTown.create({region => $usa, name => 'Dallas'});
      FpkTown.create({region => $usa, name => 'Austin'});
      expect(FpkRegion.find($usa.id).fpktowns.elems).to.eq(2);
    }

    it 'has-many returns the right rows', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      FpkTown.create({region => $usa, name => 'Dallas'});
      FpkTown.create({region => $usa, name => 'Austin'});
      expect(FpkRegion.find($usa.id).fpktowns.map(*.attrs<name>).sort.join(',')).to.eq('Austin,Dallas');
    }

    it 'belongs-to resolves the parent via override columns', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      my $dallas = FpkTown.create({region => $usa, name => 'Dallas'});
      expect(FpkTown.find($dallas.id).region.defined).to.be-truthy;
    }

    it 'belongs-to returns the right parent', {
      my $usa = FpkRegion.create({code => 'US', name => 'United States'});
      my $dallas = FpkTown.create({region => $usa, name => 'Dallas'});
      expect(FpkTown.find($dallas.id).region.attrs<code>).to.eq('US');
    }

    it 'returns no rows when no children match', {
      my $blank = FpkRegion.create({code => 'XX', name => 'Nowhere'});
      expect($blank.fpktowns.elems).to.eq(0);
    }
  }
}
