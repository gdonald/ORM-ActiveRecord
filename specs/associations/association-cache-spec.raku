use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Instrumentation::Notifications;
use Models::User;
use Models::Page;
use Models::Post;
use Models::Tag;
use Models::Profile;
use Models::Article;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'keeping a loaded association', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:counted, {
    -> &block {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });
      block();
      Notifications.unsubscribe($sub);
      @sql;
    }
  });

  let(:owner, {
    my $user = User.create({fname => 'Greg', lname => 'Donald'});
    Page.create({user => $user, name => 'Home'});
    Page.create({user => $user, name => 'About'});
    User.find($user.id);
  });

  context 'a has-many collection', {
    it 'queries once for two reads', {
      owner.pages.elems;

      expect(counted()(-> { owner.pages.elems }).elems).to.eq(0);
    }

    it 'hands back the same proxy on the second read', {
      my $first = owner.pages;

      expect(owner.pages === $first).to.be-truthy;
    }

    it 'still returns every row', {
      owner.pages.elems;

      expect(owner.pages.elems).to.eq(2);
    }

    it 'shows a push through the proxy on the next read', {
      owner.pages.push(Page.create({name => 'Contact'}));

      expect(owner.pages.elems).to.eq(3);
    }

    it 'drops what it kept on reload', {
      owner.pages.elems;

      expect(counted()(-> { owner.reload.pages.elems }).elems).to.be-greater-than(0);
    }
  }

  context 'a collection that came back empty', {
    let(:childless, { User.create({fname => 'Ann', lname => 'B'}) });

    it 'is not kept, so a record created afterward is found', {
      childless.pages.elems;
      Page.create({user => childless, name => 'Late'});

      expect(childless.pages.elems).to.eq(1);
    }
  }

  context 'a has-one', {
    it 'queries once for two reads', {
      Profile.create({user => owner, bio => 'Raku'});
      owner.profile;

      expect(counted()(-> { owner.profile }).elems).to.eq(0);
    }

    it 'is not kept while it resolves to nothing', {
      owner.profile;
      Profile.create({user => owner, bio => 'Raku'});

      expect(owner.profile.defined).to.be-truthy;
    }
  }

  context 'a belongs-to', {
    let(:page, { Page.find(owner.pages.first.id) });

    it 'queries once for two reads', {
      page.user;

      expect(counted()(-> { page.user }).elems).to.eq(0);
    }

    it 'reloads when the foreign key changes', {
      my $other = User.create({fname => 'Ann', lname => 'B'});
      page.user;
      page.attrs<user_id> = $other.id;

      expect(page.user.id).to.eq($other.id);
    }
  }

  context 'an association with a scope block', {
    it 'is not kept, since its rows depend on the call', {
      owner.published-articles.elems;

      expect(counted()(-> { owner.published-articles.elems }).elems).to.be-greater-than(0);
    }
  }

  context 'a has-and-belongs-to-many collection', {
    it 'is not kept, since the join table is written from both sides', {
      my $post = Post.create({title => 'First'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);
      $post.tags.elems;

      expect(counted()(-> { $post.tags.elems }).elems).to.be-greater-than(0);
    }

    it 'sees a link cleared through the other record', {
      my $post = Post.create({title => 'First'});
      my $tag  = Tag.create({name => 'raku'});
      $post.add-tag($tag);
      $post.tags.elems;
      $tag.clear-posts;

      expect($post.tags.elems).to.eq(0);
    }
  }
}
