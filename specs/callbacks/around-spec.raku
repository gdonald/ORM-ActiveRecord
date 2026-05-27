use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my @events;

class ArClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.around-save: -> &yield {
      @events.push: 'around-save-before';
      &yield();
      @events.push: 'around-save-after';
    };
    self.around-create: -> &yield {
      @events.push: 'around-create-before';
      &yield();
      @events.push: 'around-create-after';
    };
    self.around-update: -> &yield {
      @events.push: 'around-update-before';
      &yield();
      @events.push: 'around-update-after';
    };
    self.around-destroy: -> &yield {
      @events.push: 'around-destroy-before';
      &yield();
      @events.push: 'around-destroy-after';
    };
    self.before-save:   -> { @events.push: 'before-save' };
    self.after-save:    -> { @events.push: 'after-save'  };
    self.before-create: -> { @events.push: 'before-create' };
    self.after-create:  -> { @events.push: 'after-create'  };
    self.before-update: -> { @events.push: 'before-update' };
    self.after-update:  -> { @events.push: 'after-update'  };
    self.before-destroy: -> { @events.push: 'before-destroy' };
    self.after-destroy:  -> { @events.push: 'after-destroy'  };
  }
}

class ArHaltClient is Model {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :presence };
    self.around-save: -> &yield {
      # never yield -> halts
    };
  }
}

describe 'around callbacks', {
  before-each {
    ArClient.destroy-all;
    @events = ();
  }

  after-each {
    ArClient.destroy-all;
  }

  it 'around-save and around-create wrap before/after on insert', {
    ArClient.create({ email => 'fred@aol.com' });

    expect(@events).to.eq([
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
    ArClient.create({ email => 'fred@aol.com' });
    @events = ();

    my $c = ArClient.where({ email => 'fred@aol.com' }).first;
    $c.email = 'barney@compuserve.net';
    $c.save;

    expect(@events).to.eq([
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
    ArClient.create({ email => 'barney@compuserve.net' });
    @events = ();

    my $c = ArClient.where({ email => 'barney@compuserve.net' }).first;
    $c.destroy;

    expect(@events).to.eq([
      'around-destroy-before',
      'before-destroy',
      'after-destroy',
      'around-destroy-after',
    ]);
  }

  it 'failing to yield in around-save halts save', {
    my $c = ArHaltClient.new(:id(0), :record({ attrs => { email => 'never@save.com' } }));

    expect($c.save).to.be-falsy;
  }
}
