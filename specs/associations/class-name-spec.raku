use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;
use Models::Profile;
use Models::Magazine;
use Models::Subscription;
use Models::Post;
use Models::Tag;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'class-name option', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'belongs-to via class-name', {
    it 'saves the FK', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $page = Page.create({:$user, name => 'Raku'});
      expect($page.is-valid).to.be-truthy;
    }

    it 'fills the FK column', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $page = Page.create({:$user, name => 'Raku'});
      expect($page.attrs<user_id>).to.eq($user.id);
    }

    it 'resolves the parent class', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $page = Page.create({:$user, name => 'Raku'});
      my $fetched = Page.find($page.id);
      expect($fetched.user.WHAT === User).to.be-truthy;
    }

    it 'returns the right parent row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $page = Page.create({:$user, name => 'Raku'});
      my $fetched = Page.find($page.id);
      expect($fetched.user.id).to.eq($user.id);
    }
  }

  context 'has-many via class-name', {
    it 'returns the row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Page.create({:$user, name => 'Raku'});
      expect($user.pages.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $page = Page.create({:$user, name => 'Raku'});
      expect($user.pages.first.id).to.eq($page.id);
    }
  }

  context 'has-one via class-name', {
    it 'returns a defined row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Profile.create({:$user, bio => 'Raku enthusiast'});
      expect(User.find($user.id).profile.defined).to.be-truthy;
    }

    it 'returns the right row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $profile = Profile.create({:$user, bio => 'Raku enthusiast'});
      expect(User.find($user.id).profile.id).to.eq($profile.id);
    }
  }

  context 'has-many :through with hash-form class-name', {
    it 'returns the joined row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $magazine = Magazine.create({title => 'Mad'});
      Subscription.create({:$user, :$magazine});

      expect(User.find($user.id).magazines.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $magazine = Magazine.create({title => 'Mad'});
      Subscription.create({:$user, :$magazine});

      expect(User.find($user.id).magazines.first.id).to.eq($magazine.id);
    }
  }

  context 'has-and-belongs-to-many via class-name', {
    it 'links the row (owning side)', {
      my $post = Post.create({title => 'Hello'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($post.tags.elems).to.eq(1);
    }

    it 'returns the right row (owning side)', {
      my $post = Post.create({title => 'Hello'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($post.tags.first.id).to.eq($tag.id);
    }

    it 'links the row (inverse side)', {
      my $post = Post.create({title => 'Hello'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($tag.posts.elems).to.eq(1);
    }

    it 'returns the right row (inverse side)', {
      my $post = Post.create({title => 'Hello'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);

      expect($tag.posts.first.id).to.eq($post.id);
    }
  }

  context 'class-name resolution failure', {
    it 'dies on an unknown class-name', {
      expect({ User.resolve-class-name('Nonexistent') }).to.raise-error;
    }

    it 'mentions the offending name in the error', {
      my $msg = (try { User.resolve-class-name('Nonexistent'); '' } // $!.message);

      expect($msg).to.match(/'Nonexistent'/);
    }
  }
}
