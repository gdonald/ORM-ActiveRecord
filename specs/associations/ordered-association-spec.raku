use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Instrumentation::Notifications;
use Models::User;
use Models::Page;

%*ENV<DISABLE-SQL-LOG> = True;

# `order` on an association is declared rather than expressed through a `scope`
# block. A scoped association is neither kept between reads nor countable
# without fetching, so declaring the order keeps both.
describe 'an association declared with an order', {
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
    Page.create({user => $user, name => 'alpha'});
    Page.create({user => $user, name => 'gamma'});
    Page.create({user => $user, name => 'beta'});
    User.find($user.id);
  });

  before-each { owner }

  it 'returns the rows in the declared order', {
    expect(owner.ordered-pages.map(*.name).join(',')).to.eq('gamma,beta,alpha');
  }

  it 'leaves an unordered association alone', {
    expect(owner.pages.map(*.name).sort.join(',')).to.eq('alpha,beta,gamma');
  }

  it 'counts without fetching the rows', {
    my $pages = owner.ordered-pages;
    $pages.count;

    expect($pages.is-loaded).to.be-falsy;
  }

  it 'counts in one query', {
    expect(counted()(-> { owner.ordered-pages.count }).elems).to.eq(1);
  }

  it 'counts correctly', {
    expect(owner.ordered-pages.count).to.eq(3);
  }

  it 'is kept between reads', {
    owner.ordered-pages.elems;

    expect(counted()(-> { owner.ordered-pages.elems }).elems).to.eq(0);
  }

  it 'finds by id without fetching the rows', {
    my $wanted = Page.where({ name => 'beta' }).first;
    my $pages  = owner.ordered-pages;
    $pages.find($wanted.id);

    expect($pages.is-loaded).to.be-falsy;
  }
}
