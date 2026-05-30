use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class Citizen is Model {
  method table-name { 'users' }

  submethod BUILD {
    self.validate: 'fname', { :presence }
    self.validate: 'lname', { :presence }
  }

  method polymorphic-name { 'Person' }
}

module Bureau {
  our class Bulletin is Model {
    submethod BUILD {
      self.validate: 'title', { :presence }
    }

    method table-name { 'posts' }

    method polymorphic-name { 'Bureau::Bulletin' }
  }
}

class Sticker is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
    self.validate: 'name', { :presence }
  }
}

class Decal is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
    self.validate: 'name', { :presence }
  }

  method polymorphic-class-for(Str:D $assoc, Str:D $type) {
    given $type {
      when 'Person'        { return Citizen }
      when 'Bureau::Bulletin'   { return Bureau::Bulletin }
      default              { return Nil }
    }
  }
}

BEGIN {
  GLOBAL::<Citizen>             := Citizen;
  GLOBAL::<Bureau>              := Bureau;
  GLOBAL::<Sticker>       := Sticker;
  GLOBAL::<Decal> := Decal;
}

describe 'polymorphic resolution', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'polymorphic-name override on target', {
    it 'saves the user', {
      my $user = Citizen.create({fname => 'Greg', lname => 'Donald'});
      expect($user.id).to.be-truthy;
    }

    it 'class-level polymorphic-name returns custom string', {
      expect(Citizen.polymorphic-name).to.eq('Person');
    }

    it 'attachment saves with overridden name', {
      my $user = Citizen.create({fname => 'Greg', lname => 'Donald'});
      my $a = Sticker.create({name => 'avatar.png', attachable => $user});
      expect($a.id).to.be-truthy;
    }

    it 'attachable_type stored using override', {
      my $user = Citizen.create({fname => 'Greg', lname => 'Donald'});
      my $a = Sticker.create({name => 'avatar.png', attachable => $user});
      expect($a.attrs<attachable_type>).to.eq('Person');
    }
  }

  context 'module-qualified storage', {
    it 'post saves', {
      my $post = Bureau::Bulletin.create({title => 'Hello'});
      expect($post.id).to.be-truthy;
    }

    it 'polymorphic-name preserved', {
      expect(Bureau::Bulletin.polymorphic-name).to.eq('Bureau::Bulletin');
    }

    it 'attachable_type stored as module-qualified', {
      my $post = Bureau::Bulletin.create({title => 'Hello'});
      my $a = Sticker.create({name => 'banner.jpg', attachable => $post});
      expect($a.attrs<attachable_type>).to.eq('Bureau::Bulletin');
    }

    it 'fetched target resolves to module-qualified class', {
      my $post = Bureau::Bulletin.create({title => 'Hello'});
      my $a = Sticker.create({name => 'banner.jpg', attachable => $post});
      my $fetched = Sticker.find($a.id);
      expect($fetched.attachable.WHAT === Bureau::Bulletin).to.be-truthy;
    }

    it 'fetched target has correct id', {
      my $post = Bureau::Bulletin.create({title => 'Hello'});
      my $a = Sticker.create({name => 'banner.jpg', attachable => $post});
      my $fetched = Sticker.find($a.id);
      expect($fetched.attachable.id).to.eq($post.id);
    }
  }

  context 'polymorphic-class-for hook', {
    it 'writes using target polymorphic-name', {
      my $user = Citizen.create({fname => 'Jane', lname => 'Roe'});
      my $au = Decal.create({name => 'u.png', attachable => $user});
      expect($au.attrs<attachable_type>).to.eq('Person');
    }

    it 'hook maps "Person" back to Citizen', {
      my $user = Citizen.create({fname => 'Jane', lname => 'Roe'});
      my $au = Decal.create({name => 'u.png', attachable => $user});
      my $fetched-u = Decal.find($au.id);
      expect($fetched-u.attachable.WHAT === Citizen).to.be-truthy;
    }

    it 'hook maps "Bureau::Bulletin" back to Bureau::Bulletin', {
      my $post = Bureau::Bulletin.create({title => 'Hooked'});
      my $ap = Decal.create({name => 'p.jpg', attachable => $post});
      my $fetched-p = Decal.find($ap.id);
      expect($fetched-p.attachable.WHAT === Bureau::Bulletin).to.be-truthy;
    }

    it 'returns Nil for unknown type', {
      my $user = Citizen.create({fname => 'Anon', lname => 'Anon'});
      my $a = Decal.create({name => 'rogue.bin', attachable => $user});
      $a.attrs<attachable_type> = 'Unknown';
      $a.save(:validate(False));
      my $fetched = Decal.find($a.id);
      expect($fetched.attachable.defined).to.be-falsy;
    }
  }
}
