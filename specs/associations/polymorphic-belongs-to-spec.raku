use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PbtUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
    self.validate: 'lname', { :presence }
  }
}

class PbtPost is Model {
  method table-name { 'posts' }

  submethod BUILD {
    self.validate: 'title', { :presence }
  }
}

class PbtAttachment is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
    self.validate: 'name', { :presence }
  }
}

BEGIN {
  GLOBAL::<PbtUser>       := PbtUser;
  GLOBAL::<PbtPost>       := PbtPost;
  GLOBAL::<PbtAttachment> := PbtAttachment;
}

describe 'polymorphic belongs-to', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves the user', {
    my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
    expect($user.id).to.be-truthy;
  }

  it 'saves the post', {
    my $post = PbtPost.create({title => 'Hello'});
    expect($post.id).to.be-truthy;
  }

  context 'attachment with user', {
    it 'saves', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.id).to.be-truthy;
    }

    it 'sets attachable_id to user id', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.attrs<attachable_id>).to.eq($user.id);
    }

    it 'sets attachable_type to "PbtUser"', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      expect($a1.attrs<attachable_type>).to.eq('PbtUser');
    }
  }

  context 'attachment with post', {
    it 'saves', {
      my $post = PbtPost.create({title => 'Hello'});
      my $a2 = PbtAttachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.id).to.be-truthy;
    }

    it 'sets attachable_id to post id', {
      my $post = PbtPost.create({title => 'Hello'});
      my $a2 = PbtAttachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.attrs<attachable_id>).to.eq($post.id);
    }

    it 'sets attachable_type to "PbtPost"', {
      my $post = PbtPost.create({title => 'Hello'});
      my $a2 = PbtAttachment.create({name => 'banner.jpg', attachable => $post});
      expect($a2.attrs<attachable_type>).to.eq('PbtPost');
    }
  }

  context 'read back', {
    it 'attachable resolves to PbtUser', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      my $fetched = PbtAttachment.find($a1.id);
      expect($fetched.attachable.WHAT === PbtUser).to.be-truthy;
    }

    it 'attachable has the right id', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      my $fetched = PbtAttachment.find($a1.id);
      expect($fetched.attachable.id).to.eq($user.id);
    }

    it 'attachable resolves to PbtPost', {
      my $post = PbtPost.create({title => 'Hello'});
      my $a2 = PbtAttachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = PbtAttachment.find($a2.id);
      expect($fetched.attachable.WHAT === PbtPost).to.be-truthy;
    }

    it 'post attachable has the right id', {
      my $post = PbtPost.create({title => 'Hello'});
      my $a2 = PbtAttachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = PbtAttachment.find($a2.id);
      expect($fetched.attachable.id).to.eq($post.id);
    }
  }

  context 'switch polymorphic target via update', {
    it 'resolves to PbtPost', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $post = PbtPost.create({title => 'Hello'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      $a1.update({attachable => $post});
      my $reloaded = PbtAttachment.find($a1.id);
      expect($reloaded.attachable.WHAT === PbtPost).to.be-truthy;
    }

    it 'updates attachable_type', {
      my $user = PbtUser.create({fname => 'Greg', lname => 'Donald'});
      my $post = PbtPost.create({title => 'Hello'});
      my $a1 = PbtAttachment.create({name => 'avatar.png', attachable => $user});
      $a1.update({attachable => $post});
      my $reloaded = PbtAttachment.find($a1.id);
      expect($reloaded.attrs<attachable_type>).to.eq('PbtPost');
    }
  }

  context 'unset polymorphic', {
    it 'saves', {
      my $bare = PbtAttachment.create({name => 'unattached.txt'});
      expect($bare.id).to.be-truthy;
    }

    it 'reads as Nil', {
      my $bare = PbtAttachment.create({name => 'unattached.txt'});
      expect($bare.attachable.defined).to.be-falsy;
    }

    it 'unset _id stays 0', {
      my $bare = PbtAttachment.create({name => 'unattached.txt'});
      expect($bare.attrs<attachable_id>).to.eq(0);
    }
  }
}
