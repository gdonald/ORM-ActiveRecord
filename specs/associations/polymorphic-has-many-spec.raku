use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PhmPicture {...}

class PhmUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.has-many: pictures => %(class => PhmPicture, as => 'imageable');
  }
}

class PhmPost is Model {
  method table-name { 'posts' }

  submethod BUILD {
    self.has-many: pictures => %(class => PhmPicture, as => 'imageable');
  }
}

class PhmPicture is Model {
  method table-name { 'pictures' }

  submethod BUILD {
    self.belongs-to: imageable => :polymorphic;
  }
}

BEGIN {
  GLOBAL::<PhmUser>    := PhmUser;
  GLOBAL::<PhmPost>    := PhmPost;
  GLOBAL::<PhmPicture> := PhmPicture;
}

describe 'polymorphic has-many :as', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves the user', {
    my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
    expect($user.id).to.be-truthy;
  }

  it 'saves the post', {
    my $post = PhmPost.create({title => 'Hello'});
    expect($post.id).to.be-truthy;
  }

  it 'user has no pictures initially', {
    my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
    expect($user.pictures.elems).to.eq(0);
  }

  it 'post has no pictures initially', {
    my $post = PhmPost.create({title => 'Hello'});
    expect($post.pictures.elems).to.eq(0);
  }

  it 'pictures save for both owners', {
    my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
    my $post = PhmPost.create({title => 'Hello'});
    my $u-pic-a = PhmPicture.create({name => 'avatar.png',   imageable => $user});
    my $u-pic-b = PhmPicture.create({name => 'banner.jpg',   imageable => $user});
    my $p-pic-a = PhmPicture.create({name => 'hero.png',     imageable => $post});

    expect($u-pic-a.id && $u-pic-b.id && $p-pic-a.id).to.be-truthy;
  }

  context 'user pictures', {
    it 'has exactly 2 via :as scope', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      PhmPicture.create({name => 'avatar.png', imageable => $user});
      PhmPicture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      PhmPicture.create({name => 'avatar.png', imageable => $user});
      PhmPicture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.map(*.attrs<name>).sort.join(',')).to.eq('avatar.png,banner.jpg');
    }

    it 'all carry imageable_type "PhmUser"', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      PhmPicture.create({name => 'avatar.png', imageable => $user});
      PhmPicture.create({name => 'banner.jpg', imageable => $user});

      expect($user.pictures.grep({ .attrs<imageable_type> eq 'PhmUser' }).elems).to.eq(2);
    }
  }

  context 'post pictures', {
    it 'has exactly 1 via :as scope', {
      my $post = PhmPost.create({title => 'Hello'});
      PhmPicture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures.elems).to.eq(1);
    }

    it 'returns the right row', {
      my $post = PhmPost.create({title => 'Hello'});
      PhmPicture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures[0].attrs<name>).to.eq('hero.png');
    }

    it 'all carry imageable_type "PhmPost"', {
      my $post = PhmPost.create({title => 'Hello'});
      PhmPicture.create({name => 'hero.png', imageable => $post});

      expect($post.pictures.grep({ .attrs<imageable_type> eq 'PhmPost' }).elems).to.eq(1);
    }
  }

  context 'round-trip polymorphic to parent', {
    it 'resolves to PhmUser', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      my $u-pic = PhmPicture.create({name => 'avatar.png', imageable => $user});

      expect($u-pic.imageable.WHAT === PhmUser).to.be-truthy;
    }

    it 'resolves to PhmPost', {
      my $post = PhmPost.create({title => 'Hello'});
      my $p-pic = PhmPicture.create({name => 'hero.png', imageable => $post});

      expect($p-pic.imageable.WHAT === PhmPost).to.be-truthy;
    }
  }

  context 'reassignment of polymorphic parent', {
    it 'user picture count drops', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      my $post = PhmPost.create({title => 'Hello'});
      PhmPicture.create({name => 'avatar.png', imageable => $user});
      my $u-pic-b = PhmPicture.create({name => 'banner.jpg', imageable => $user});
      PhmPicture.create({name => 'hero.png', imageable => $post});
      $u-pic-b.update({imageable => $post});

      expect(PhmUser.find($user.id).pictures.elems).to.eq(1);
    }

    it 'post picture count rises', {
      my $user = PhmUser.create({fname => 'Greg', lname => 'Donald'});
      my $post = PhmPost.create({title => 'Hello'});
      PhmPicture.create({name => 'avatar.png', imageable => $user});
      my $u-pic-b = PhmPicture.create({name => 'banner.jpg', imageable => $user});
      PhmPicture.create({name => 'hero.png', imageable => $post});
      $u-pic-b.update({imageable => $post});

      expect(PhmPost.find($post.id).pictures.elems).to.eq(2);
    }
  }
}
