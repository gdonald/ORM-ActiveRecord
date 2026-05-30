use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Post;
use Models::Picture;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'polymorphic has-many :as', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves the user', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    expect($user.id).to.be-truthy;
  }

  it 'saves the post', {
    my $post = Post.create({title => 'Hello'});
    expect($post.id).to.be-truthy;
  }

  it 'user has no pictures initially', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    expect($user.pictures.elems).to.eq(0);
  }

  it 'post has no pictures initially', {
    my $post = Post.create({title => 'Hello'});
    expect($post.pictures.elems).to.eq(0);
  }

  it 'pictures save for both owners', {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    my $post = Post.create({title => 'Hello'});
    my $u-pic-a = Picture.create({name => 'avatar.png',   imageable => $user});
    my $u-pic-b = Picture.create({name => 'banner.jpg',   imageable => $user});
    my $p-pic-a = Picture.create({name => 'hero.png',     imageable => $post});

    expect($u-pic-a.id && $u-pic-b.id && $p-pic-a.id).to.be-truthy;
  }

  context 'user pictures', {
    it 'has exactly 2 via :as scope', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Picture.create({name => 'avatar.png', imageable => $user});
      Picture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Picture.create({name => 'avatar.png', imageable => $user});
      Picture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.map(*.attrs<name>).sort.join(',')).to.eq('avatar.png,banner.jpg');
    }

    it 'all carry imageable_type "User"', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      Picture.create({name => 'avatar.png', imageable => $user});
      Picture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.grep({ .attrs<imageable_type> eq 'User' }).elems).to.eq(2);
    }
  }

  context 'post pictures', {
    it 'has exactly 1 via :as scope', {
      my $post = Post.create({title => 'Hello'});
      Picture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $post = Post.create({title => 'Hello'});
      Picture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures[0].attrs<name>).to.eq('hero.png');
    }

    it 'all carry imageable_type "Post"', {
      my $post = Post.create({title => 'Hello'});
      Picture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures.grep({ .attrs<imageable_type> eq 'Post' }).elems).to.eq(1);
    }
  }

  context 'round-trip polymorphic to parent', {
    it 'resolves to User', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $u-pic = Picture.create({name => 'avatar.png', imageable => $user});

      expect($u-pic.imageable.WHAT === User).to.be-truthy;
    }

    it 'resolves to Post', {
      my $post = Post.create({title => 'Hello'});
      my $p-pic = Picture.create({name => 'hero.png', imageable => $post});

      expect($p-pic.imageable.WHAT === Post).to.be-truthy;
    }
  }

  context 'reassignment of polymorphic parent', {
    it 'user picture count drops', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $post = Post.create({title => 'Hello'});
      Picture.create({name => 'avatar.png', imageable => $user});
      my $u-pic-b = Picture.create({name => 'banner.jpg', imageable => $user});
      Picture.create({name => 'hero.png', imageable => $post});
      $u-pic-b.update({imageable => $post});

      expect(User.find($user.id).pictures.elems).to.eq(1);
    }

    it 'post picture count rises', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $post = Post.create({title => 'Hello'});
      Picture.create({name => 'avatar.png', imageable => $user});
      my $u-pic-b = Picture.create({name => 'banner.jpg', imageable => $user});
      Picture.create({name => 'hero.png', imageable => $post});
      $u-pic-b.update({imageable => $post});

      expect(Post.find($post.id).pictures.elems).to.eq(2);
    }
  }
}
