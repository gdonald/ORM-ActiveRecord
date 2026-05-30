use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Post;
use Models::Picture;
use Models::Attachment;

%*ENV<DISABLE-SQL-LOG> = True;

sub pel-seed {
  clean-shared-tables;

  my %h;
  %h<alice> = User.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = User.create({fname => 'Bob',   lname => 'B'});
  %h<p1>    = Post.create({title => 'Hello'});
  %h<p2>    = Post.create({title => 'World'});

  Picture.create({name => 'a-avatar.png', imageable => %h<alice>});
  Picture.create({name => 'a-banner.jpg', imageable => %h<alice>});
  Picture.create({name => 'b-avatar.png', imageable => %h<bob>});
  Picture.create({name => 'p1-hero.png',  imageable => %h<p1>});

  Attachment.create({name => 'a-doc.txt',  attachable => %h<alice>});
  Attachment.create({name => 'a-spec.txt', attachable => %h<alice>});
  Attachment.create({name => 'b-doc.txt',  attachable => %h<bob>});
  Attachment.create({name => 'p1-doc.txt', attachable => %h<p1>});
  Attachment.create({name => 'p2-doc.txt', attachable => %h<p2>});
  Attachment.create({name => 'orphan.txt'});

  %h;
}

describe 'polymorphic eager loading', {
  before-each { pel-seed }
  after-each  { clean-shared-tables }

  context 'preload polymorphic belongs-to', {
    it 'loads every attachment', {
      my @atts = Attachment.where({}).preload(:attachable).all;
      expect(@atts.elems).to.eq(6);
    }

    it 'populates assoc-cache', {
      my @atts = Attachment.where({}).preload(:attachable).all;
      expect(@atts.first.assoc-cache<attachable>:exists).to.be-truthy;
    }

    it 'resolves User type', {
      my @atts = Attachment.where({}).preload(:attachable).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.WHAT === User).to.be-truthy;
    }

    it 'returns correct User id', {
      my %h = pel-seed;
      my @atts = Attachment.where({}).preload(:attachable).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.id).to.eq(%h<alice>.id);
    }

    it 'resolves Post type', {
      my @atts = Attachment.where({}).preload(:attachable).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.WHAT === Post).to.be-truthy;
    }

    it 'returns correct Post id', {
      my %h = pel-seed;
      my @atts = Attachment.where({}).preload(:attachable).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.id).to.eq(%h<p1>.id);
    }

    it 'leaves orphans as Nil', {
      my @atts = Attachment.where({}).preload(:attachable).all;
      my $orphan = @atts.first({ .attrs<name> eq 'orphan.txt' });
      expect($orphan.attachable.defined).to.be-falsy;
    }
  }

  context 'preload polymorphic has-many :as', {
    it 'caches collection on user', {
      my @users = User.where({}).preload(:pictures).all;
      expect(@users.first.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'returns correct collection size for Alice', {
      my @users = User.where({}).preload(:pictures).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pictures.elems).to.eq(2);
    }

    it 'returns correct rows for Alice', {
      my @users = User.where({}).preload(:pictures).all;
      my $alice-loaded = @users.first({ .attrs<fname> eq 'Alice' });
      expect($alice-loaded.pictures.map(*.attrs<name>).sort.join(',')).to.eq('a-avatar.png,a-banner.jpg');
    }

    it 'returns Bob one row', {
      my @users = User.where({}).preload(:pictures).all;
      my $bob-loaded = @users.first({ .attrs<fname> eq 'Bob' });
      expect($bob-loaded.pictures.elems).to.eq(1);
    }

    it 'returns matching rows on Post', {
      my @posts = Post.where({}).preload(:pictures).all;
      my $p1-loaded = @posts.first({ .attrs<title> eq 'Hello' });
      expect($p1-loaded.pictures.elems).to.eq(1);
    }

    it 'returns right row on Post', {
      my @posts = Post.where({}).preload(:pictures).all;
      my $p1-loaded = @posts.first({ .attrs<title> eq 'Hello' });
      expect($p1-loaded.pictures[0].attrs<name>).to.eq('p1-hero.png');
    }

    it 'empty collection when no matches', {
      my @posts = Post.where({}).preload(:pictures).all;
      my $p2-loaded = @posts.first({ .attrs<title> eq 'World' });
      expect($p2-loaded.pictures.elems).to.eq(0);
    }
  }

  it 'includes polymorphic belongs-to caches via preload path', {
    my @atts = Attachment.where({}).includes(:attachable).all;
    expect(@atts.first.assoc-cache<attachable>:exists).to.be-truthy;
  }

  context 'eager-load on polymorphic belongs-to', {
    it 'raises', {
      expect({ Attachment.where({}).eager-load(:attachable).all }).to.raise-error;
    }

    it 'error mentions polymorphic', {
      my $threw = False;
      my $msg;
      {
        CATCH { default { $threw = True; $msg = .message } }
        Attachment.where({}).eager-load(:attachable).all;
      }
      expect(($msg // '').contains('polymorphic')).to.be-truthy;
    }
  }

  context 'nested preload from polymorphic belongs-to', {
    it 'caches on User parent', {
      my @atts = Attachment.where({}).preload(attachable => :pictures).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'correct count for User parent', {
      my @atts = Attachment.where({}).preload(attachable => :pictures).all;
      my $a1 = @atts.first({ .attrs<name> eq 'a-doc.txt' });
      expect($a1.attachable.pictures.elems).to.eq(2);
    }

    it 'caches on Post parent', {
      my @atts = Attachment.where({}).preload(attachable => :pictures).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.assoc-cache<pictures>:exists).to.be-truthy;
    }

    it 'correct count for Post parent', {
      my @atts = Attachment.where({}).preload(attachable => :pictures).all;
      my $p1-att = @atts.first({ .attrs<name> eq 'p1-doc.txt' });
      expect($p1-att.attachable.pictures.elems).to.eq(1);
    }
  }
}
