use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::Post;
use Models::Tag;
use ORM::ActiveRecord::Instrumentation::Notifications;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-and-belongs-to-many', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves a fresh post', {
    my $post = Post.create({title => 'First'});

    expect($post.is-valid).to.be-truthy;
  }

  it 'has no tags on a fresh post', {
    my $post = Post.create({title => 'First'});

    expect($post.tags.elems).to.eq(0);
  }

  it 'has no posts on a fresh tag', {
    Post.create({title => 'First'});
    my $tag = Tag.create({name => 'ruby'});

    expect($tag.posts.elems).to.eq(0);
  }

  context 'after two add-tags', {
    it 'returns two tags', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      my $raku = Tag.create({name => 'raku'});
      $post.add-tag($ruby);
      $post.add-tag($raku);

      expect($post.tags.elems).to.eq(2);
    }

    it 'links the right rows', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      my $raku = Tag.create({name => 'raku'});
      $post.add-tag($ruby);
      $post.add-tag($raku);

      expect($post.tags.map(*.id).sort.list).to.eq(($ruby.id, $raku.id).sort.list);
    }

    it 'is visible from the inverse side', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      $post.add-tag($ruby);

      expect($ruby.posts.first.id).to.eq($post.id);
    }
  }

  it 'add is additive', {
    my $post = Post.create({title => 'First'});
    my $ruby = Tag.create({name => 'ruby'});
    my $raku = Tag.create({name => 'raku'});
    my $orm  = Tag.create({name => 'orm'});
    $post.add-tag($ruby);
    $post.add-tag($raku);
    $post.add-tag($orm);

    expect($post.tags.elems).to.eq(3);
  }

  context 'after remove-tag', {
    it 'drops the count by one', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      my $raku = Tag.create({name => 'raku'});
      my $orm  = Tag.create({name => 'orm'});
      $post.add-tag($ruby);
      $post.add-tag($raku);
      $post.add-tag($orm);
      $post.remove-tag($raku);

      expect($post.tags.elems).to.eq(2);
    }

    it 'drops the right link', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      my $raku = Tag.create({name => 'raku'});
      my $orm  = Tag.create({name => 'orm'});
      $post.add-tag($ruby);
      $post.add-tag($raku);
      $post.add-tag($orm);
      $post.remove-tag($raku);

      expect($post.tags.map(*.id).sort.list).to.eq(($ruby.id, $orm.id).sort.list);
    }
  }

  context 'after clear-tags', {
    it 'empties the collection', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      $post.add-tag($ruby);
      $post.clear-tags;

      expect($post.tags.elems).to.eq(0);
    }

    it 'is visible from the inverse side', {
      my $post = Post.create({title => 'First'});
      my $ruby = Tag.create({name => 'ruby'});
      $post.add-tag($ruby);
      $post.clear-tags;

      expect($ruby.posts.elems).to.eq(0);
    }
  }

  context 'inverse-side writes', {
    it 'links the row from the inverse side', {
      my $post = Post.create({title => 'First'});
      my $raku = Tag.create({name => 'raku'});
      $raku.add-post($post);

      expect($raku.posts.first.id).to.eq($post.id);
    }

    it 'is visible from the owning side', {
      my $post = Post.create({title => 'First'});
      my $raku = Tag.create({name => 'raku'});
      $raku.add-post($post);

      expect($post.tags.first.id).to.eq($raku.id);
    }

    it 'inverse-side clear empties the join table', {
      my $post = Post.create({title => 'First'});
      my $raku = Tag.create({name => 'raku'});
      $raku.add-post($post);
      $raku.clear-posts;

      expect($post.tags.elems).to.eq(0);
    }
  }
}

describe 'preloading a has-and-belongs-to-many association', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:built, {
    my $ruby = Tag.create({name => 'ruby'});
    my $raku = Tag.create({name => 'raku'});
    my $perl = Tag.create({name => 'perl'});

    my $first  = Post.create({title => 'First'});
    my $second = Post.create({title => 'Second'});
    my $third  = Post.create({title => 'Third'});

    $first.add-tag($ruby);
    $first.add-tag($raku);
    $second.add-tag($perl);

    %( :$first, :$second, :$third, :$ruby, :$raku, :$perl );
  });

  let(:counted, {
    -> &block {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });
      block();
      Notifications.unsubscribe($sub);
      @sql;
    }
  });

  it 'gives each owner its own tags', {
    built;
    my @posts = Post.includes('tags').order('id').all;

    expect(@posts[0].tags.map(*.name).sort.list).to.eq(('raku', 'ruby'));
  }

  it 'gives a second owner its own tags', {
    built;
    my @posts = Post.includes('tags').order('id').all;

    expect(@posts[1].tags.map(*.name).list).to.eq(('perl',));
  }

  it 'gives an owner with no tags an empty collection', {
    built;
    my @posts = Post.includes('tags').order('id').all;

    expect(@posts[2].tags.elems).to.eq(0);
  }

  it 'reads the owners, their join rows, and their tags in three queries', {
    built;

    expect(counted()(-> { Post.includes('tags').order('id').all }).elems).to.eq(3);
  }

  it 'does not add a query when another owner joins the load', {
    built;
    Post.create({title => 'Fourth'}).add-tag(Tag.create({name => 'zig'}));

    expect(counted()(-> { Post.includes('tags').order('id').all }).elems).to.eq(3);
  }

  it 'serves the preloaded tags without another query', {
    built;
    my @posts = Post.includes('tags').order('id').all;

    expect(counted()(-> { .tags.elems for @posts }).elems).to.eq(0);
  }

  it 'preloads the inverse side too', {
    built;
    my @tags = Tag.includes('posts').order('id').all;

    expect(@tags[0].posts.map(*.title).list).to.eq(('First',));
  }
}
