use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS pel_pictures');
  $adapter.exec('DROP TABLE IF EXISTS pel_attachments');
  $adapter.exec('DROP TABLE IF EXISTS pel_posts');
  $adapter.exec('DROP TABLE IF EXISTS pel_users');

  $adapter.ddl-create-table('pel_users', [
    fname => { :string, limit => 32 },
    lname => { :string, limit => 32 },
  ]);

  $adapter.ddl-create-table('pel_posts', [
    title => { :string, limit => 80 },
  ]);

  $adapter.ddl-create-table('pel_pictures', [
    name      => { :string, limit => 80 },
    imageable => { :reference, :polymorphic },
  ]);

  $adapter.ddl-create-table('pel_attachments', [
    name       => { :string, limit => 80 },
    attachable => { :reference, :polymorphic },
  ]);
}

class PelPicture {...}

class PelUser is Model {
  method table-name { 'pel_users' }

  submethod BUILD {
    self.has-many: pictures => %(class => PelPicture, as => 'imageable');
  }
}

class PelPost is Model {
  method table-name { 'pel_posts' }

  submethod BUILD {
    self.has-many: pictures => %(class => PelPicture, as => 'imageable');
  }
}

class PelPicture is Model {
  method table-name { 'pel_pictures' }

  submethod BUILD {
    self.belongs-to: imageable => :polymorphic;
  }
}

class PelAttachment is Model {
  method table-name { 'pel_attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
  }
}

BEGIN {
  GLOBAL::<PelUser>       := PelUser;
  GLOBAL::<PelPost>       := PelPost;
  GLOBAL::<PelPicture>    := PelPicture;
  GLOBAL::<PelAttachment> := PelAttachment;
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS pel_pictures');
    try $adapter.exec('DROP TABLE IF EXISTS pel_attachments');
    try $adapter.exec('DROP TABLE IF EXISTS pel_posts');
    try $adapter.exec('DROP TABLE IF EXISTS pel_users');
  }
}

sub pel-seed {
  clean-shared-tables;
  PelPicture.destroy-all;
  PelAttachment.destroy-all;
  PelPost.destroy-all;
  PelUser.destroy-all;

  my %h;
  %h<alice> = PelUser.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = PelUser.create({fname => 'Bob',   lname => 'B'});
  %h<p1>    = PelPost.create({title => 'Hello'});
  %h<p2>    = PelPost.create({title => 'World'});

  PelPicture.create({name => 'a-avatar.png', imageable => %h<alice>});
  PelPicture.create({name => 'a-banner.jpg', imageable => %h<alice>});
  PelPicture.create({name => 'b-avatar.png', imageable => %h<bob>});
  PelPicture.create({name => 'p1-hero.png',  imageable => %h<p1>});

  PelAttachment.create({name => 'a-doc.txt',  attachable => %h<alice>});
  PelAttachment.create({name => 'a-spec.txt', attachable => %h<alice>});
  PelAttachment.create({name => 'b-doc.txt',  attachable => %h<bob>});
  PelAttachment.create({name => 'p1-doc.txt', attachable => %h<p1>});
  PelAttachment.create({name => 'p2-doc.txt', attachable => %h<p2>});
  PelAttachment.create({name => 'orphan.txt'});

  %h;
}

sub pel-clean {
  clean-shared-tables;
  PelPicture.destroy-all;
  PelAttachment.destroy-all;
  PelPost.destroy-all;
  PelUser.destroy-all;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'polymorphic eager loading', {
  before-each { pel-seed }
  after-each  { pel-clean }

  context 'preload polymorphic belongs-to', {
    it 'loads every attachment', {
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      expect(@atts.elems).to.eq(6);
    }

    it 'populates assoc-cache', {
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      expect(@atts.first.assoc-cache<attachable>:exists).to.be-truthy;
    }

    it 'resolves PelUser type', {
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.WHAT === PelUser).to.be-truthy;
    }

    it 'returns correct PelUser id', {
      my %h = pel-seed;
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.id).to.eq(%h<alice>.id);
    }

    it 'resolves PelPost type', {
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.WHAT === PelPost).to.be-truthy;
    }

    it 'returns correct PelPost id', {
      my %h = pel-seed;
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.id).to.eq(%h<p1>.id);
    }

    it 'leaves orphans as Nil', {
      my @atts = PelAttachment.where({}).preload(:attachable).all;
      my $orphan = @atts.first({ .attrs<name> eq 'orphan.txt' });
      expect($orphan.attachable.defined).to.be-falsy;
    }
  }

  context 'preload polymorphic has-many :as', {
    it 'caches collection on user', {
      my @users = PelUser.where({}).preload(:pictures).all;
      expect(@users.first.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'returns correct collection size for Alice', {
      my @users = PelUser.where({}).preload(:pictures).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pictures.elems).to.eq(2);
    }

    it 'returns correct rows for Alice', {
      my @users = PelUser.where({}).preload(:pictures).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pictures.map(*.attrs<name>).sort.join(',')).to.eq('a-avatar.png,a-banner.jpg');
    }

    it 'returns Bob one row', {
      my @users = PelUser.where({}).preload(:pictures).all;
      my $bob-loaded = @users.first({ .attrs<fname> eq 'Bob' });
      expect($bob-loaded.pictures.elems).to.eq(1);
    }

    it 'returns matching rows on Post', {
      my @posts = PelPost.where({}).preload(:pictures).all;
      my $p1-loaded = @posts.first({ .attrs<title> eq 'Hello' });
      expect($p1-loaded.pictures.elems).to.eq(1);
    }

    it 'returns right row on Post', {
      my @posts = PelPost.where({}).preload(:pictures).all;
      my $p1-loaded = @posts.first({ .attrs<title> eq 'Hello' });
      expect($p1-loaded.pictures[0].attrs<name>).to.eq('p1-hero.png');
    }

    it 'empty collection when no matches', {
      my @posts = PelPost.where({}).preload(:pictures).all;
      my $p2-loaded = @posts.first({ .attrs<title> eq 'World' });
      expect($p2-loaded.pictures.elems).to.eq(0);
    }
  }

  it 'includes polymorphic belongs-to caches via preload path', {
    my @atts = PelAttachment.where({}).includes(:attachable).all;
    expect(@atts.first.assoc-cache<attachable>:exists).to.be-truthy;
  }

  context 'eager-load on polymorphic belongs-to', {
    it 'raises', {
      expect({ PelAttachment.where({}).eager-load(:attachable).all }).to.raise-error;
    }

    it 'error mentions polymorphic', {
      my $threw = False;
      my $msg;
      {
        CATCH { default { $threw = True; $msg = .message } }
        PelAttachment.where({}).eager-load(:attachable).all;
      }
      expect(($msg // '').contains('polymorphic')).to.be-truthy;
    }
  }

  context 'nested preload from polymorphic belongs-to', {
    it 'caches on PelUser parent', {
      my @atts = PelAttachment.where({}).preload(attachable => :pictures).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'correct count for PelUser parent', {
      my @atts = PelAttachment.where({}).preload(attachable => :pictures).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.pictures.elems).to.eq(2);
    }

    it 'caches on PelPost parent', {
      my @atts = PelAttachment.where({}).preload(attachable => :pictures).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'correct count for PelPost parent', {
      my @atts = PelAttachment.where({}).preload(attachable => :pictures).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.pictures.elems).to.eq(1);
    }
  }
}
