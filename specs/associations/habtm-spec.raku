use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class HtTag {...}

class HtPost is Model {
  method table-name { 'posts' }
  method fkey-name  { 'post_id' }

  submethod BUILD {
    self.has-and-belongs-to-many: tags => %(class => HtTag, join-table => 'posts_tags');
  }
}

class HtTag is Model {
  method table-name { 'tags' }
  method fkey-name  { 'tag_id' }

  submethod BUILD {
    self.has-and-belongs-to-many: posts => %(class => HtPost, join-table => 'posts_tags');
  }
}

describe 'has-and-belongs-to-many', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'saves a fresh post', {
    my $post = HtPost.create({title => 'First'});

    expect($post.is-valid).to.be-truthy;
  }

  it 'has no tags on a fresh post', {
    my $post = HtPost.create({title => 'First'});

    expect($post.tags.elems).to.eq(0);
  }

  it 'has no posts on a fresh tag', {
    HtPost.create({title => 'First'});
    my $tag = HtTag.create({name => 'ruby'});

    expect($tag.posts.elems).to.eq(0);
  }

  context 'after two add-tags', {
    it 'returns two tags', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      my $raku = HtTag.create({name => 'raku'});
      $post.add-tag($ruby);
      $post.add-tag($raku);

      expect($post.tags.elems).to.eq(2);
    }

    it 'links the right rows', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      my $raku = HtTag.create({name => 'raku'});
      $post.add-tag($ruby);
      $post.add-tag($raku);

      expect($post.tags.map(*.id).sort.list).to.eq(($ruby.id, $raku.id).sort.list);
    }

    it 'is visible from the inverse side', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      $post.add-tag($ruby);

      expect($ruby.posts.first.id).to.eq($post.id);
    }
  }

  it 'add is additive', {
    my $post = HtPost.create({title => 'First'});
    my $ruby = HtTag.create({name => 'ruby'});
    my $raku = HtTag.create({name => 'raku'});
    my $orm  = HtTag.create({name => 'orm'});
    $post.add-tag($ruby);
    $post.add-tag($raku);
    $post.add-tag($orm);

    expect($post.tags.elems).to.eq(3);
  }

  context 'after remove-tag', {
    it 'drops the count by one', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      my $raku = HtTag.create({name => 'raku'});
      my $orm  = HtTag.create({name => 'orm'});
      $post.add-tag($ruby);
      $post.add-tag($raku);
      $post.add-tag($orm);
      $post.remove-tag($raku);

      expect($post.tags.elems).to.eq(2);
    }

    it 'drops the right link', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      my $raku = HtTag.create({name => 'raku'});
      my $orm  = HtTag.create({name => 'orm'});
      $post.add-tag($ruby);
      $post.add-tag($raku);
      $post.add-tag($orm);
      $post.remove-tag($raku);

      expect($post.tags.map(*.id).sort.list).to.eq(($ruby.id, $orm.id).sort.list);
    }
  }

  context 'after clear-tags', {
    it 'empties the collection', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      $post.add-tag($ruby);
      $post.clear-tags;

      expect($post.tags.elems).to.eq(0);
    }

    it 'is visible from the inverse side', {
      my $post = HtPost.create({title => 'First'});
      my $ruby = HtTag.create({name => 'ruby'});
      $post.add-tag($ruby);
      $post.clear-tags;

      expect($ruby.posts.elems).to.eq(0);
    }
  }

  context 'inverse-side writes', {
    it 'links the row from the inverse side', {
      my $post = HtPost.create({title => 'First'});
      my $raku = HtTag.create({name => 'raku'});
      $raku.add-post($post);

      expect($raku.posts.first.id).to.eq($post.id);
    }

    it 'is visible from the owning side', {
      my $post = HtPost.create({title => 'First'});
      my $raku = HtTag.create({name => 'raku'});
      $raku.add-post($post);

      expect($post.tags.first.id).to.eq($raku.id);
    }

    it 'inverse-side clear empties the join table', {
      my $post = HtPost.create({title => 'First'});
      my $raku = HtTag.create({name => 'raku'});
      $raku.add-post($post);
      $raku.clear-posts;

      expect($post.tags.elems).to.eq(0);
    }
  }
}
