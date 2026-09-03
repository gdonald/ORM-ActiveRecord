use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Instrumentation::Notifications;
use Models::User;
use Models::Page;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'a has-many collection before its rows are fetched', {
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

  # Build the owner and its rows outside the blocks that count queries, so a
  # count reflects only the read under test.
  before-each { owner }

  it 'queries nothing when the accessor is called', {
    expect(counted()(-> { owner.pages }).elems).to.eq(0);
  }

  it 'reports itself unloaded until something reads the rows', {
    expect(owner.pages.is-loaded).to.be-falsy;
  }

  it 'reports itself loaded once the rows are read', {
    my $pages = owner.pages;
    $pages.elems;

    expect($pages.is-loaded).to.be-truthy;
  }

  context 'counting', {
    it 'counts in one query', {
      expect(counted()(-> { owner.pages.count }).elems).to.eq(1);
    }

    it 'counts without fetching the rows', {
      my $pages = owner.pages;
      $pages.count;

      expect($pages.is-loaded).to.be-falsy;
    }

    it 'gives the same answer as fetching the rows', {
      expect(owner.pages.count).to.eq(2);
    }

    it 'counts from memory once the rows are here', {
      my $pages = owner.pages;
      $pages.elems;

      expect(counted()(-> { $pages.count }).elems).to.eq(0);
    }

    it 'answers size the same way', {
      expect(owner.pages.size).to.eq(2);
    }

    it 'answers length the same way', {
      expect(owner.pages.length).to.eq(2);
    }
  }

  context 'counting one column', {
    before-each {
      Page.create({user => owner, name => Str});
    }

    it 'counts only the rows where the column is set', {
      expect(owner.pages.count('name')).to.eq(2);
    }

    it 'counts without fetching the rows', {
      my $pages = owner.pages;
      $pages.count('name');

      expect($pages.is-loaded).to.be-falsy;
    }

    it 'takes one query', {
      expect(counted()(-> { owner.pages.count('name') }).elems).to.eq(1);
    }

    it 'gives the same answer once the rows are here', {
      my $pages = owner.pages;
      $pages.elems;

      expect($pages.count('name')).to.eq(2);
    }
  }

  context 'asking whether anything is there', {
    it 'answers is-any in one query', {
      expect(counted()(-> { owner.pages.is-any }).elems).to.eq(1);
    }

    it 'answers is-any without fetching the rows', {
      my $pages = owner.pages;
      $pages.is-any;

      expect($pages.is-loaded).to.be-falsy;
    }

    it 'says a populated association is not empty', {
      expect(owner.pages.is-empty).to.be-falsy;
    }

    it 'says an association with no rows is empty', {
      my $childless = User.create({fname => 'Ann', lname => 'B'});

      expect($childless.pages.is-empty).to.be-truthy;
    }
  }

  context 'looking one record up', {
    it 'finds by id without fetching the rows', {
      my $wanted = Page.where({ name => 'About' }).first;
      my $pages  = owner.pages;
      $pages.find($wanted.id);

      expect($pages.is-loaded).to.be-falsy;
    }

    it 'finds the right record', {
      my $wanted = Page.where({ name => 'About' }).first;

      expect(owner.pages.find($wanted.id).name).to.eq('About');
    }

    it 'refuses an id the association does not hold', {
      my $stranger = Page.create({name => 'Orphan'});

      expect({ owner.pages.find($stranger.id) }).to.throw(X::RecordNotFound);
    }

    it 'reports an id it holds as existing', {
      my $wanted = Page.where({ name => 'About' }).first;

      expect(owner.pages.exists($wanted.id)).to.be-truthy;
    }

    it 'reports an id it does not hold as missing', {
      my $stranger = Page.create({name => 'Orphan'});

      expect(owner.pages.exists($stranger.id)).to.be-falsy;
    }
  }

  context 'an association a single relation cannot express', {
    it 'counts a through association by fetching its rows', {
      my $pages = owner.magazines;
      $pages.count;

      expect($pages.is-loaded).to.be-truthy;
    }
  }

  # Membership is kept as a set of ids, so a push is constant time rather than a
  # scan of everything already in the collection.
  context 'membership', {
    it 'does not add a record the collection already holds', {
      my $already = owner.pages.first;
      owner.pages.push($already);

      expect(owner.pages.count).to.eq(2);
    }

    it 'adds a record it does not hold', {
      owner.pages.push(Page.create({name => 'New'}));

      expect(owner.pages.count).to.eq(3);
    }

    it 'reports a member as existing', {
      my $member = owner.pages.first;

      expect(owner.pages.exists($member.id)).to.be-truthy;
    }

    it 'stops reporting a deleted record as existing', {
      my $member = owner.pages.first;
      owner.pages.delete($member);

      expect(owner.pages.exists($member.id)).to.be-falsy;
    }

    it 'reports a record pushed after a delete as existing', {
      my $member = owner.pages.first;
      owner.pages.delete($member);
      owner.pages.push(Page.create({name => 'Later'}));

      expect(owner.pages.count).to.eq(2);
    }

    it 'stops reporting anything as existing after a clear', {
      my $member = owner.pages.first;
      owner.pages.clear;

      expect(owner.pages.exists($member.id)).to.be-falsy;
    }
  }

  context 'writing through the proxy', {
    it 'fetches the rows before appending a created record', {
      owner.pages.create({name => 'Contact'});

      expect(owner.pages.count).to.eq(3);
    }

    it 'fetches the rows before pushing', {
      owner.pages.push(Page.create({name => 'Pushed'}));

      expect(owner.pages.count).to.eq(3);
    }

    it 'fetches the rows before clearing', {
      owner.pages.clear;

      expect(owner.pages.count).to.eq(0);
    }
  }
}
