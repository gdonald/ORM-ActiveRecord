use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS core_widgets');
  $adapter.ddl-create-table('core_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('core_widgets');
}

class CoreWidget is Model {
  method table-name { 'core_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS core_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'DB.transaction commit path', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'commits inserts when the block returns normally', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'committed', qty => 1 });
    });

    expect(CoreWidget.count).to.eq(1);
  }

  it 'resets is-in-transaction to False after commit', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'committed', qty => 1 });
    });

    expect(DB.shared.is-in-transaction).to.be-falsy;
  }
}

group 'DB.transaction with an unhandled exception', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'lets the exception escape', {
    expect({
      DB.shared.transaction({
        CoreWidget.create({ name => 'doomed', qty => 1 });
        die 'boom';
      });
    }).to.raise-error;
  }

  it 'rolls back any inserts', {
    try {
      DB.shared.transaction({
        CoreWidget.create({ name => 'doomed', qty => 1 });
        die 'boom';
      });
    }

    expect(CoreWidget.count).to.eq(0);
  }

  it 'resets is-in-transaction to False after rollback', {
    try {
      DB.shared.transaction({
        CoreWidget.create({ name => 'doomed', qty => 1 });
        die 'boom';
      });
    }

    expect(DB.shared.is-in-transaction).to.be-falsy;
  }
}

group 'DB.transaction with X::Rollback', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'swallows X::Rollback', {
    expect({
      DB.shared.transaction({
        CoreWidget.create({ name => 'aborted', qty => 1 });
        die X::Rollback.new(:reason<test>);
      });
    }).not.to.raise-error;
  }

  it 'rolls back inserts on X::Rollback', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'aborted', qty => 1 });
      die X::Rollback.new(:reason<test>);
    });

    expect(CoreWidget.count).to.eq(0);
  }

  it 'resets is-in-transaction depth to 0', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'aborted', qty => 1 });
      die X::Rollback.new(:reason<test>);
    });

    expect(DB.shared.is-in-transaction).to.be-falsy;
  }
}

group 'nested DB.transaction without requires-new', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'propagates an inner die', {
    expect({
      DB.shared.transaction({
        CoreWidget.create({ name => 'outer', qty => 1 });
        DB.shared.transaction({
          CoreWidget.create({ name => 'inner', qty => 2 });
          die 'inner boom';
        });
      });
    }).to.raise-error;
  }

  it 'rolls back the entire outer transaction on inner failure', {
    try {
      DB.shared.transaction({
        CoreWidget.create({ name => 'outer', qty => 1 });
        DB.shared.transaction({
          CoreWidget.create({ name => 'inner', qty => 2 });
          die 'inner boom';
        });
      });
    }

    expect(CoreWidget.count).to.eq(0);
  }
}

group 'savepoint with requires-new', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'does not propagate the savepoint rollback', {
    expect({
      DB.shared.transaction({
        CoreWidget.create({ name => 'outer', qty => 1 });
        DB.shared.transaction(:requires-new, {
          CoreWidget.create({ name => 'sp-doomed', qty => 9 });
          die X::Rollback.new;
        });
        CoreWidget.create({ name => 'after-sp', qty => 3 });
      });
    }).not.to.raise-error;
  }

  it 'keeps the outer transaction inserts', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'outer', qty => 1 });
      DB.shared.transaction(:requires-new, {
        CoreWidget.create({ name => 'sp-doomed', qty => 9 });
        die X::Rollback.new;
      });
      CoreWidget.create({ name => 'after-sp', qty => 3 });
    });

    expect(CoreWidget.count).to.eq(2);
  }

  it 'drops only the inner insert from the savepoint', {
    DB.shared.transaction({
      CoreWidget.create({ name => 'outer', qty => 1 });
      DB.shared.transaction(:requires-new, {
        CoreWidget.create({ name => 'sp-doomed', qty => 9 });
        die X::Rollback.new;
      });
      CoreWidget.create({ name => 'after-sp', qty => 3 });
    });

    my @names = CoreWidget.all.pluck('name').sort;
    expect(@names.join(',')).to.eq('after-sp,outer');
  }
}

group 'savepoint exception that escapes', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'propagates the savepoint exception to the outer block', {
    expect({
      DB.shared.transaction({
        CoreWidget.create({ name => 'outer-2', qty => 1 });
        DB.shared.transaction(:requires-new, {
          die 'savepoint boom';
        });
        CoreWidget.create({ name => 'never-reached', qty => 99 });
      });
    }).to.raise-error;
  }

  it 'rolls back the outer transaction when the savepoint exception escapes', {
    try {
      DB.shared.transaction({
        CoreWidget.create({ name => 'outer-2', qty => 1 });
        DB.shared.transaction(:requires-new, {
          die 'savepoint boom';
        });
        CoreWidget.create({ name => 'never-reached', qty => 99 });
      });
    }

    expect(CoreWidget.count).to.eq(0);
  }
}

group 'is-in-transaction flag', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'is False before any transaction starts', {
    expect(DB.shared.is-in-transaction).to.be-falsy;
  }

  it 'is True inside the block', {
    my $saw-flag = False;
    DB.shared.transaction({
      $saw-flag = DB.shared.is-in-transaction;
    });

    expect($saw-flag).to.be-truthy;
  }

  it 'clears after commit', {
    DB.shared.transaction({ True });

    expect(DB.shared.is-in-transaction).to.be-falsy;
  }
}

group 'DB.transaction return value', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'returns the block value', {
    my $result = DB.shared.transaction({ 42 });

    expect($result).to.eq(42);
  }
}

group 'isolation levels', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'accepts an isolation level on the outer transaction', {
    expect({
      DB.shared.transaction(:isolation<read_committed>, { 1 });
    }).not.to.raise-error;
  }

  it 'rejects an isolation level on a nested transaction', {
    expect({
      DB.shared.transaction({
        DB.shared.transaction(:isolation<serializable>, { 1 });
      });
    }).to.raise-error;
  }

  it 'rejects an unknown isolation level', {
    expect({
      DB.shared.transaction(:isolation<bananas>, { 1 });
    }).to.raise-error;
  }

  it 'does not leave a dangling transaction after a failed isolation level', {
    try { DB.shared.transaction(:isolation<bananas>, { 1 }) }

    expect(DB.shared.is-in-transaction).to.be-falsy;
  }
}

group 'Model.transaction', {
  before-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
    CoreWidget.destroy-all;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
  }

  it 'wraps DB.transaction', {
    CoreWidget.transaction({
      CoreWidget.create({ name => 'via-model', qty => 5 });
    });

    expect(CoreWidget.count).to.eq(1);
  }
}
