use lib 'lib';
use BDD::Behave;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

class PlainGadget is Model {
  method table-name { 'plain_gadgets' }
}

class AnalyticsGadget is Model {
  method table-name { 'analytics_gadgets' }
}

AnalyticsGadget.connects-to('analytics');

my &group = $has-sqlite ?? &describe !! &xdescribe;

describe 'connects-to binding', {
  it 'defaults an unbound model to the primary connection', {
    expect(PlainGadget.connection-name).to.eq('primary');
  }

  it 'binds a model to a named connection', {
    expect(AnalyticsGadget.connection-name).to.eq('analytics');
  }

  it 'does not leak one model binding onto another', {
    expect(PlainGadget.connection-name).to.eq('primary');
  }
}

group 'connects-to routing', :tag<destructive>, {
  my $saved-primary;
  my $primary-adapter;
  my $analytics-adapter;

  before-all {
    if $has-sqlite {
      $saved-primary = DB.shared(name => 'primary');

      $primary-adapter   = SqliteAdapter.new(database => ':memory:');
      $analytics-adapter = SqliteAdapter.new(database => ':memory:');

      DB.set-shared(DB.new(adapter => $primary-adapter),   name => 'primary');
      DB.set-shared(DB.new(adapter => $analytics-adapter), name => 'analytics');

      # The bound model's table lives only in the analytics connection.
      $analytics-adapter.ddl-create-table('analytics_gadgets', [
        name => { :string, limit => 64 },
      ]);
    }
  }

  after-all {
    if $has-sqlite {
      DB.set-shared($saved-primary, name => 'primary');
      DB.set-shared(Nil, name => 'analytics');
    }
  }

  context 'a record created through a bound model', {
    before-each {
      $analytics-adapter.exec('DELETE FROM analytics_gadgets') if $has-sqlite;
    }

    it 'persists to the bound connection', {
      AnalyticsGadget.create({ name => 'Alpha' });

      expect($analytics-adapter.count-records(table => 'analytics_gadgets', where => {}))
        .to.eq(1);
    }

    it 'does not create the table on the primary connection', {
      AnalyticsGadget.create({ name => 'Alpha' });

      expect('analytics_gadgets' (elem) $primary-adapter.get-table-names.list)
        .to.be-falsy;
    }

    it 'finds records through the bound connection', {
      AnalyticsGadget.create({ name => 'Beta' });

      expect(AnalyticsGadget.all.elems).to.eq(1);
    }
  }
}
