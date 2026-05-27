use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class PrUser is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
    self.validate: 'lname', { :presence }
  }

  method polymorphic-name { 'Person' }
}

module PrApp {
  our class Post is Model {
    submethod BUILD {
      self.validate: 'title', { :presence }
    }

    method table-name { 'posts' }

    method polymorphic-name { 'PrApp::Post' }
  }
}

class PrAttachment is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
    self.validate: 'name', { :presence }
  }
}

class PrMappedAttachment is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
    self.validate: 'name', { :presence }
  }

  method polymorphic-class-for(Str:D $assoc, Str:D $type) {
    given $type {
      when 'Person'        { return PrUser }
      when 'PrApp::Post'   { return PrApp::Post }
      default              { return Nil }
    }
  }
}

BEGIN {
  GLOBAL::<PrUser>             := PrUser;
  GLOBAL::<PrApp>              := PrApp;
  GLOBAL::<PrAttachment>       := PrAttachment;
  GLOBAL::<PrMappedAttachment> := PrMappedAttachment;
}

describe 'polymorphic resolution', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'polymorphic-name override on target', {
    it 'saves the user', {
      my $user = PrUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.id).to.be-truthy;
    }

    it 'class-level polymorphic-name returns custom string', {
      expect(PrUser.polymorphic-name).to.eq('Person');
    }

    it 'attachment saves with overridden name', {
      my $user = PrUser.create({fname => 'Greg', lname => 'Donald'});
      my $a = PrAttachment.create({name => 'avatar.png', attachable => $user});
      expect($a.id).to.be-truthy;
    }

    it 'attachable_type stored using override', {
      my $user = PrUser.create({fname => 'Greg', lname => 'Donald'});
      my $a = PrAttachment.create({name => 'avatar.png', attachable => $user});
      expect($a.attrs<attachable_type>).to.eq('Person');
    }
  }

  context 'module-qualified storage', {
    it 'post saves', {
      my $post = PrApp::Post.create({title => 'Hello'});
      expect($post.id).to.be-truthy;
    }

    it 'polymorphic-name preserved', {
      expect(PrApp::Post.polymorphic-name).to.eq('PrApp::Post');
    }

    it 'attachable_type stored as module-qualified', {
      my $post = PrApp::Post.create({title => 'Hello'});
      my $a = PrAttachment.create({name => 'banner.jpg', attachable => $post});
      expect($a.attrs<attachable_type>).to.eq('PrApp::Post');
    }

    it 'fetched target resolves to module-qualified class', {
      my $post = PrApp::Post.create({title => 'Hello'});
      my $a = PrAttachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = PrAttachment.find($a.id);
      expect($fetched.attachable.WHAT === PrApp::Post).to.be-truthy;
    }

    it 'fetched target has correct id', {
      my $post = PrApp::Post.create({title => 'Hello'});
      my $a = PrAttachment.create({name => 'banner.jpg', attachable => $post});
      my $fetched = PrAttachment.find($a.id);
      expect($fetched.attachable.id).to.eq($post.id);
    }
  }

  context 'polymorphic-class-for hook', {
    it 'writes using target polymorphic-name', {
      my $user = PrUser.create({fname => 'Jane', lname => 'Roe'});
      my $au = PrMappedAttachment.create({name => 'u.png', attachable => $user});
      expect($au.attrs<attachable_type>).to.eq('Person');
    }

    it 'hook maps "Person" back to PrUser', {
      my $user = PrUser.create({fname => 'Jane', lname => 'Roe'});
      my $au = PrMappedAttachment.create({name => 'u.png', attachable => $user});
      my $fetched-u = PrMappedAttachment.find($au.id);
      expect($fetched-u.attachable.WHAT === PrUser).to.be-truthy;
    }

    it 'hook maps "PrApp::Post" back to PrApp::Post', {
      my $post = PrApp::Post.create({title => 'Hooked'});
      my $ap = PrMappedAttachment.create({name => 'p.jpg', attachable => $post});
      my $fetched-p = PrMappedAttachment.find($ap.id);
      expect($fetched-p.attachable.WHAT === PrApp::Post).to.be-truthy;
    }

    it 'returns Nil for unknown type', {
      my $user = PrUser.create({fname => 'Anon', lname => 'Anon'});
      my $a = PrMappedAttachment.create({name => 'rogue.bin', attachable => $user});
      $a.attrs<attachable_type> = 'Unknown';
      $a.save(:validate(False));
      my $fetched = PrMappedAttachment.find($a.id);
      expect($fetched.attachable.defined).to.be-falsy;
    }
  }
}
