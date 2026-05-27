use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CnPage {...}
class CnProfile {...}
class CnMagazine {...}
class CnSubscription {...}
class CnPost {...}
class CnTag {...}

class CnUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: cnpages => %(class-name => 'CnPage', foreign-key => 'user_id');
    self.has-many: subscriptions => %(class-name => 'CnSubscription', foreign-key => 'user_id');
    self.has-many: magazines => %(through => :subscriptions, class-name => 'CnMagazine', source => 'cnmagazine');
    self.has-one:  cnprofile => %(class-name => 'CnProfile', foreign-key => 'user_id');
  }
}

class CnPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: cnuser => %(class-name => 'CnUser', foreign-key => 'user_id');
  }
}

class CnProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: cnuser => %(class-name => 'CnUser', foreign-key => 'user_id');
  }
}

class CnMagazine is Model {
  method table-name { 'magazines' }
  method fkey-name  { 'magazine_id' }
}

class CnSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: cnuser    => %(class-name => 'CnUser',     foreign-key => 'user_id');
    self.belongs-to: cnmagazine => %(class-name => 'CnMagazine', foreign-key => 'magazine_id');
  }
}

class CnPost is Model {
  method table-name { 'posts' }
  method fkey-name  { 'post_id' }

  submethod BUILD {
    self.has-and-belongs-to-many: tags => %(class-name => 'CnTag', join-table => 'posts_tags');
  }
}

class CnTag is Model {
  method table-name { 'tags' }
  method fkey-name  { 'tag_id' }

  submethod BUILD {
    self.has-and-belongs-to-many: posts => %(class-name => 'CnPost', join-table => 'posts_tags');
  }
}

BEGIN {
  GLOBAL::<CnUser>         := CnUser;
  GLOBAL::<CnPage>         := CnPage;
  GLOBAL::<CnProfile>      := CnProfile;
  GLOBAL::<CnMagazine>     := CnMagazine;
  GLOBAL::<CnSubscription> := CnSubscription;
  GLOBAL::<CnPost>         := CnPost;
  GLOBAL::<CnTag>          := CnTag;
}

describe 'class-name option', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'belongs-to via class-name', {
    it 'saves the FK', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $page = CnPage.create({cnuser => $user, name => 'Raku'});
      expect($page.is-valid).to.be-truthy;
    }

    it 'fills the FK column', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $page = CnPage.create({cnuser => $user, name => 'Raku'});
      expect($page.attrs<user_id>).to.eq($user.id);
    }

    it 'resolves the parent class', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $page = CnPage.create({cnuser => $user, name => 'Raku'});
      my $fetched = CnPage.find($page.id);
      expect($fetched.cnuser.WHAT === CnUser).to.be-truthy;
    }

    it 'returns the right parent row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $page = CnPage.create({cnuser => $user, name => 'Raku'});
      my $fetched = CnPage.find($page.id);
      expect($fetched.cnuser.id).to.eq($user.id);
    }
  }

  context 'has-many via class-name', {
    it 'returns the row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      CnPage.create({cnuser => $user, name => 'Raku'});
      expect($user.cnpages.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $page = CnPage.create({cnuser => $user, name => 'Raku'});
      expect($user.cnpages.first.id).to.eq($page.id);
    }
  }

  context 'has-one via class-name', {
    it 'returns a defined row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      CnProfile.create({cnuser => $user, bio => 'Raku enthusiast'});
      expect(CnUser.find($user.id).cnprofile.defined).to.be-truthy;
    }

    it 'returns the right row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $profile = CnProfile.create({cnuser => $user, bio => 'Raku enthusiast'});
      expect(CnUser.find($user.id).cnprofile.id).to.eq($profile.id);
    }
  }

  context 'has-many :through with hash-form class-name', {
    it 'returns the joined row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $mag  = CnMagazine.create({title => 'Mad'});
      CnSubscription.create({cnuser => $user, cnmagazine => $mag});

      expect(CnUser.find($user.id).magazines.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = CnUser.create({fname => 'Greg', lname => 'Donald'});
      my $mag  = CnMagazine.create({title => 'Mad'});
      CnSubscription.create({cnuser => $user, cnmagazine => $mag});

      expect(CnUser.find($user.id).magazines.first.id).to.eq($mag.id);
    }
  }

  context 'has-and-belongs-to-many via class-name', {
    it 'links the row (owning side)', {
      my $post = CnPost.create({title => 'Hello'});
      my $tag  = CnTag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($post.tags.elems).to.eq(1);
    }

    it 'returns the right row (owning side)', {
      my $post = CnPost.create({title => 'Hello'});
      my $tag  = CnTag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($post.tags.first.id).to.eq($tag.id);
    }

    it 'links the row (inverse side)', {
      my $post = CnPost.create({title => 'Hello'});
      my $tag  = CnTag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($tag.posts.elems).to.eq(1);
    }

    it 'returns the right row (inverse side)', {
      my $post = CnPost.create({title => 'Hello'});
      my $tag  = CnTag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($tag.posts.first.id).to.eq($post.id);
    }
  }

  context 'class-name resolution failure', {
    it 'dies on an unknown class-name', {
      expect({ CnUser.resolve-class-name('Nonexistent') }).to.raise-error;
    }

    it 'mentions the offending name in the error', {
      my $msg = (try { CnUser.resolve-class-name('Nonexistent'); '' } // $!.message);

      expect($msg).to.match(/'Nonexistent'/);
    }
  }
}
