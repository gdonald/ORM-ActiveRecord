use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Callbacks::Around;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'around callbacks', {
  before-each {
    Client.destroy-all;
    @Callbacks::Around::events = ();
  }

  after-each {
    Client.destroy-all;
  }

  it 'around-save and around-create wrap before/after on insert', {
    Client.create({ email => 'fred@aol.com' });

    expect(@Callbacks::Around::events).to.eq([
      'around-save-before',
      'before-save',
      'around-create-before',
      'before-create',
      'after-create',
      'around-create-after',
      'after-save',
      'around-save-after',
    ]);
  }

  it 'around-save and around-update wrap before/after on update', {
    Client.create({ email => 'fred@aol.com' });
    @Callbacks::Around::events = ();

    my $c = Client.where({ email => 'fred@aol.com' }).first;
    $c.email = 'barney@compuserve.net';
    $c.save;

    expect(@Callbacks::Around::events).to.eq([
      'around-save-before',
      'before-save',
      'around-update-before',
      'before-update',
      'after-update',
      'around-update-after',
      'after-save',
      'around-save-after',
    ]);
  }

  it 'around-destroy wraps before- and after-destroy', {
    Client.create({ email => 'barney@compuserve.net' });
    @Callbacks::Around::events = ();

    my $c = Client.where({ email => 'barney@compuserve.net' }).first;
    $c.destroy;

    expect(@Callbacks::Around::events).to.eq([
      'around-destroy-before',
      'before-destroy',
      'after-destroy',
      'around-destroy-after',
    ]);
  }

  it 'failing to yield in around-save halts save', {
    my $c = HaltClient.new(:id(0), :record({ attrs => { email => 'never@save.com' } }));

    expect($c.save).to.be-falsy;
  }
}
