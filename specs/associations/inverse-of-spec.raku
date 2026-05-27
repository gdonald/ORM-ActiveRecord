use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class IoPage    {...}
class IoProfile {...}
class IoArticle {...}

class IoUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: iopages    => %(class => IoPage,    foreign-key => 'user_id', inverse-of => :iouser);
    self.has-one:  ioprofile  => %(class => IoProfile, foreign-key => 'user_id', inverse-of => :iouser);
    self.has-many: ioarticles => %(
      class       => IoArticle,
      foreign-key => 'author_id',
      inverse-of  => :scribe,
    );
  }
}

class IoPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: iouser => %(class => IoUser, foreign-key => 'user_id');
  }
}

class IoProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: iouser => %(class => IoUser, foreign-key => 'user_id');
  }
}

class IoArticle is Model {
  method table-name { 'articles' }

  submethod BUILD {
    self.belongs-to: scribe => %(class => IoUser, foreign-key => 'author_id');
  }
}

class IoEmployee is Model {
  method table-name { 'employees' }
  method fkey-name  { 'manager_id' }

  submethod BUILD {
    self.belongs-to: manager => %(class => IoEmployee, optional => True);
    self.has-many: subordinates => %(class => IoEmployee, foreign-key => 'manager_id');
  }
}

BEGIN {
  GLOBAL::<IoUser>     := IoUser;
  GLOBAL::<IoPage>     := IoPage;
  GLOBAL::<IoProfile>  := IoProfile;
  GLOBAL::<IoArticle>  := IoArticle;
  GLOBAL::<IoEmployee> := IoEmployee;
}

sub io-clean {
  clean-shared-tables;
}

describe 'inverse-of', {
  before-each { io-clean }
  after-each  { io-clean }

  context 'auto-detected has-many → belongs-to', {
    it 'returns both pages', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoPage.create({iouser => $u-seed, name => 'Home'});
      IoPage.create({iouser => $u-seed, name => 'About'});

      expect(IoUser.find($u-seed.id).iopages.elems).to.eq(2);
    }

    it 'populates back-pointer on first child', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoPage.create({iouser => $u-seed, name => 'Home'});
      IoPage.create({iouser => $u-seed, name => 'About'});
      my $owner = IoUser.find($u-seed.id);
      my @pages = $owner.iopages;

      expect(@pages.first.iouser.WHERE).to.eq($owner.WHERE);
    }

    it 'populates back-pointer on every child', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoPage.create({iouser => $u-seed, name => 'Home'});
      IoPage.create({iouser => $u-seed, name => 'About'});
      my $owner = IoUser.find($u-seed.id);
      my @pages = $owner.iopages;

      expect(@pages[1].iouser.WHERE).to.eq($owner.WHERE);
    }

    it 're-applies on re-access', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoPage.create({iouser => $u-seed, name => 'Home'});
      my $owner = IoUser.find($u-seed.id);
      $owner.iopages;
      my @pages-again = $owner.iopages;

      expect(@pages-again.first.iouser.WHERE).to.eq($owner.WHERE);
    }
  }

  context 'auto-detected has-one → belongs-to', {
    it 'returns a profile', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoProfile.create({iouser => $u-seed, bio => 'inverse-of test'});
      my $owner2 = IoUser.find($u-seed.id);

      expect($owner2.ioprofile.defined).to.be-truthy;
    }

    it 'populates back-pointer on has-one', {
      my $u-seed = IoUser.create({fname => 'Alice', lname => 'A'});
      IoProfile.create({iouser => $u-seed, bio => 'inverse-of test'});
      my $owner2 = IoUser.find($u-seed.id);
      my $prof = $owner2.ioprofile;

      expect($prof.iouser.WHERE).to.eq($owner2.WHERE);
    }
  }

  context 'explicit inverse-of with foreign-key override', {
    it 'returns rows', {
      my $author = IoUser.create({fname => 'Greg', lname => 'D'});
      IoArticle.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      IoArticle.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = IoUser.find($author.id);

      expect($writer.ioarticles.elems).to.eq(2);
    }

    it 'populates back-pointer on first child', {
      my $author = IoUser.create({fname => 'Greg', lname => 'D'});
      IoArticle.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      IoArticle.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = IoUser.find($author.id);
      my @articles = $writer.ioarticles;

      expect(@articles.first.scribe.WHERE).to.eq($writer.WHERE);
    }

    it 'populates back-pointer on every child', {
      my $author = IoUser.create({fname => 'Greg', lname => 'D'});
      IoArticle.new(:id(0), :record({attrs => {title => 'Hi', body => 'world', author_id => $author.id}})).save;
      IoArticle.new(:id(0), :record({attrs => {title => 'Yo', body => 'world', author_id => $author.id}})).save;
      my $writer = IoUser.find($author.id);
      my @articles = $writer.ioarticles;

      expect(@articles[1].scribe.WHERE).to.eq($writer.WHERE);
    }
  }

  context 'override without inverse-of disables auto-detection', {
    it 'flags as disabled', {
      my $spec = %(class => IoArticle, foreign-key => 'author_id');
      expect(IoUser.new(:id(0)).assoc-auto-inverse-disabled($spec)).to.be-truthy;
    }

    it 'resolve-inverse-name returns empty', {
      my $spec = %(class => IoArticle, foreign-key => 'author_id');
      expect(IoUser.new(:id(0)).resolve-inverse-name($spec, IoArticle)).to.eq('');
    }
  }

  context 'overrides without inverse-of, each access reloads independently', {
    it 'returns the row', {
      my $boss = IoEmployee.create({name => 'Big'});
      IoEmployee.create({name => 'Min', manager => $boss});
      my $boss-loaded = IoEmployee.find($boss.id);
      my @subs = $boss-loaded.subordinates;

      expect(@subs.elems).to.eq(1);
    }

    it 'back-pointer is a fresh load', {
      my $boss = IoEmployee.create({name => 'Big'});
      IoEmployee.create({name => 'Min', manager => $boss});
      my $boss-loaded = IoEmployee.find($boss.id);
      my @subs = $boss-loaded.subordinates;

      expect(@subs.first.manager.WHERE != $boss-loaded.WHERE).to.be-truthy;
    }
  }

  context 'direct method coverage', {
    it 'auto-detect picks single matching belongs-to', {
      my $page-spec = IoUser.new(:id(0)).has-manys<iopages>;
      expect(IoUser.new(:id(0)).resolve-inverse-name($page-spec, IoPage)).to.eq('iouser');
    }

    it 'explicit inverse-of wins even with overrides', {
      my $art-spec = IoUser.new(:id(0)).has-manys<ioarticles>;
      expect(IoUser.new(:id(0)).resolve-inverse-name($art-spec, IoArticle)).to.eq('scribe');
    }

    it 'assoc-inverse-name reads Pair-form as string', {
      my $art-spec = IoUser.new(:id(0)).has-manys<ioarticles>;
      expect(IoUser.new(:id(0)).assoc-inverse-name($art-spec)).to.eq('scribe');
    }

    it 'assoc-inverse-name accepts plain string', {
      my $str-spec = %(class => IoArticle, inverse-of => 'scribe');
      expect(IoUser.new(:id(0)).assoc-inverse-name($str-spec)).to.eq('scribe');
    }
  }
}
