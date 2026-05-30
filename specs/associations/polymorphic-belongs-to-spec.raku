use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Post;
use Models::Attachment;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'polymorphic belongs-to', {
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

  context 'attachment with user', {
    it 'saves', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.id).to.be-truthy;
    }

    it 'sets attachable_id to user id', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.attrs<attachable_id>).to.eq($user.id);
    }

    it 'sets attachable_type to "User"', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.attrs<attachable_type>).to.eq('User');
    }
  }

  context 'attachment with post', {
    it 'saves', {
      my $post = Post.create({title => 'Hello'});
      my $a2 = Attachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.id).to.be-truthy;
    }

    it 'sets attachable_id to post id', {
      my $post = Post.create({title => 'Hello'});
      my $a2 = Attachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.attrs<attachable_id>).to.eq($post.id);
    }

    it 'sets attachable_type to "Post"', {
      my $post = Post.create({title => 'Hello'});
      my $a2 = Attachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.attrs<attachable_type>).to.eq('Post');
    }
  }

  context 'read back', {
    it 'attachable resolves to User', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      my $fetched = Attachment.find($a1.id);
      expect($fetched.attachable.WHAT === User).to.be-truthy;
    }

    it 'attachable has the right id', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      my $fetched = Attachment.find($a1.id);
      expect($fetched.attachable.id).to.eq($user.id);
    }

    it 'attachable resolves to Post', {
      my $post = Post.create({title => 'Hello'});
      my $a2 = Attachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = Attachment.find($a2.id);
      expect($fetched.attachable.WHAT === Post).to.be-truthy;
    }

    it 'post attachable has the right id', {
      my $post = Post.create({title => 'Hello'});
      my $a2 = Attachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = Attachment.find($a2.id);
      expect($fetched.attachable.id).to.eq($post.id);
    }
  }

  context 'switch polymorphic target via update', {
    it 'resolves to Post', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $post = Post.create({title => 'Hello'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      $a1.update({attachable => $post});
      my $reloaded = Attachment.find($a1.id);
      expect($reloaded.attachable.WHAT === Post).to.be-truthy;
    }

    it 'updates attachable_type', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $post = Post.create({title => 'Hello'});
      my $a1 = Attachment.create({name => 'avatar.png', attachable => $user});
      $a1.update({attachable => $post});
      my $reloaded = Attachment.find($a1.id);
      expect($reloaded.attrs<attachable_type>).to.eq('Post');
    }
  }

  context 'unset polymorphic', {
    it 'saves', {
      my $bare = Attachment.create({name => 'unattached.txt'});
      expect($bare.id).to.be-truthy;
    }

    it 'reads as Nil', {
      my $bare = Attachment.create({name => 'unattached.txt'});
      expect($bare.attachable.defined).to.be-falsy;
    }

    it 'unset _id stays 0', {
      my $bare = Attachment.create({name => 'unattached.txt'});
      expect($bare.attrs<attachable_id>).to.eq(0);
    }
  }
}
