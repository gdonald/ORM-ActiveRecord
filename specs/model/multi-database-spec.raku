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
use ORM::ActiveRecord::Connection::Switching;

class RoleModel is Model { method table-name { 'role_models' } }
RoleModel.connects-to(database => { writing => 'm_primary', reading => 'm_replica' });

class ShardModel is Model { method table-name { 'shard_models' } }
ShardModel.connects-to(shards => {
  default   => { writing => 'sh_default_w', reading => 'sh_default_r' },
  shard_one => { writing => 'sh_one_w',     reading => 'sh_one_r' },
});

class LegacyModel is Model { method table-name { 'legacy_models' } }
LegacyModel.connects-to('legacy_conn');

class UnboundModel is Model { method table-name { 'unbound_models' } }

describe 'role-based connection routing', {
  it 'defaults to the writing role', {
    expect(RoleModel.connection-name).to.eq('m_primary');
  }

  it 'switches to the reading role inside connected-to', {
    expect(RoleModel.connected-to(role => 'reading', { RoleModel.connection-name })).to.eq('m_replica');
  }

  it 'restores the role after the block', {
    RoleModel.connected-to(role => 'reading', { 1 });
    expect(RoleModel.connection-name).to.eq('m_primary');
  }
}

describe 'shard-based connection routing', {
  it 'defaults to the default shard writing connection', {
    expect(ShardModel.connection-name).to.eq('sh_default_w');
  }

  it 'switches shard inside connected-to', {
    expect(ShardModel.connected-to(shard => 'shard_one', { ShardModel.connection-name })).to.eq('sh_one_w');
  }

  it 'switches shard and role together', {
    expect(ShardModel.connected-to(shard => 'shard_one', role => 'reading', { ShardModel.connection-name })).to.eq('sh_one_r');
  }

  it 'inherits the outer context in a nested block', {
    my $name = ShardModel.connected-to(role => 'reading', {
      ShardModel.connected-to(shard => 'shard_one', { ShardModel.connection-name });
    });
    expect($name).to.eq('sh_one_r');
  }
}

describe 'explicit connection override', {
  it 'connected-to(connection) wins over the role binding', {
    expect(RoleModel.connected-to(connection => 'override', { RoleModel.connection-name })).to.eq('override');
  }

  it 'overrides even an unbound model', {
    expect(UnboundModel.connected-to(connection => 'override', { UnboundModel.connection-name })).to.eq('override');
  }
}

describe 'connected-to-many', {
  it 'switches the role for every model in the block', {
    my $names = Model.connected-to-many([RoleModel, ShardModel], role => 'reading', {
      RoleModel.connection-name ~ ',' ~ ShardModel.connection-name;
    });
    expect($names).to.eq('m_replica,sh_default_r');
  }
}

describe 'legacy single-connection binding', {
  it 'binds to the single connection', {
    expect(LegacyModel.connection-name).to.eq('legacy_conn');
  }

  it 'is unaffected by role switching', {
    expect(LegacyModel.connected-to(role => 'reading', { LegacyModel.connection-name })).to.eq('legacy_conn');
  }
}

describe 'unbound model', {
  it 'uses the primary connection', {
    expect(UnboundModel.connection-name).to.eq('primary');
  }

  it 'ignores role and shard switching', {
    expect(UnboundModel.connected-to(role => 'reading', shard => 'shard_one', { UnboundModel.connection-name })).to.eq('primary');
  }
}

describe 'DatabaseSelector', :order<defined>, {
  it 'reads by default', {
    expect(DatabaseSelector.new.role-for).to.eq('reading');
  }

  it 'writes when a write is requested', {
    expect(DatabaseSelector.new.role-for(:write)).to.eq('writing');
  }

  it 'sticks to writing within the delay window after a write', {
    my $sel = DatabaseSelector.new(delay => 5);
    $sel.record-write;
    expect($sel.role-for).to.eq('writing');
  }

  it 'returns to reading once the delay window passes', {
    my $sel = DatabaseSelector.new(delay => 0.01);
    $sel.record-write;
    sleep 0.05;
    expect($sel.role-for).to.eq('reading');
  }
}

my &group = $has-sqlite ?? &describe !! &xdescribe;

group 'role routing end to end', :tag<destructive>, :order<defined>, {
  my $saved-primary;
  my $writing-adapter;
  my $reading-adapter;

  before-all {
    if $has-sqlite {
      $saved-primary   = DB.shared(name => 'primary');
      $writing-adapter = SqliteAdapter.new(database => ':memory:');
      $reading-adapter = SqliteAdapter.new(database => ':memory:');

      DB.set-shared(DB.new(adapter => $writing-adapter), name => 'm_primary');
      DB.set-shared(DB.new(adapter => $reading-adapter), name => 'm_replica');

      # Same table in both connections; only the writing one gets the row.
      for $writing-adapter, $reading-adapter -> $a {
        $a.ddl-create-table('role_models', [ name => { :string, limit => 64 } ]);
      }

      RoleModel.create({ name => 'Alpha' });
    }
  }

  after-all {
    if $has-sqlite {
      DB.set-shared($saved-primary, name => 'primary');
      DB.set-shared(Nil, name => 'm_primary');
      DB.set-shared(Nil, name => 'm_replica');
    }
  }

  it 'writes through the writing connection', {
    expect($writing-adapter.count-records(table => 'role_models', where => {})).to.eq(1);
  }

  it 'reads default to the writing connection', {
    expect(RoleModel.count).to.eq(1);
  }

  it 'reads from the reading connection inside connected-to(role => reading)', {
    expect(RoleModel.connected-to(role => 'reading', { RoleModel.count })).to.eq(0);
  }
}
