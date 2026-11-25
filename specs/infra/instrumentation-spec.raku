use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Instrumentation::Notifications;
use ORM::ActiveRecord::Instrumentation::QueryLogs;
use ORM::ActiveRecord::Instrumentation::LogSubscriber;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS instr_widgets');
  $adapter.ddl-create-table('instr_widgets', [ name => { :string, limit => 64 } ]);
}

class InstrWidget is Model {
  method table-name { 'instr_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS instr_widgets') if $has-db;
}

sub reset-instrumentation {
  LogSubscriber.reset;
  QueryLogs.reset;
  Notifications.reset;
}

describe 'Notifications pub/sub', :order<defined>, {
  before-each { reset-instrumentation }
  after-each  { reset-instrumentation }

  it 'delivers a payload to a subscriber', {
    my @got;
    Notifications.subscribe('e.test', -> %p { @got.push: %p });
    Notifications.notify('e.test', { x => 1 });
    expect(@got[0]<x>).to.eq(1);
  }

  it 'reports active subscribers', {
    Notifications.subscribe('e.test', -> %p { });
    expect(Notifications.has-subscribers('e.test')).to.be-truthy;
  }

  it 'stops delivering after unsubscribe', {
    my $id = Notifications.subscribe('e.test', -> %p { });
    Notifications.unsubscribe($id);
    expect(Notifications.has-subscribers('e.test')).to.be-falsy;
  }

  it 'returns the block result from instrument', {
    Notifications.subscribe('e.timed', -> %p { });
    expect(Notifications.instrument('e.timed', { }, { 42 })).to.eq(42);
  }

  it 'adds a numeric duration to the instrumented payload', {
    my @got;
    Notifications.subscribe('e.timed', -> %p { @got.push: %p });
    Notifications.instrument('e.timed', { }, { 1 });
    expect(@got[0]<duration> ~~ Numeric).to.be-truthy;
  }

  it 'notifies the start event before the block runs', {
    my @order;
    Notifications.subscribe('e.started.start', -> %p { @order.push: 'start' });
    Notifications.subscribe('e.started', -> %p { @order.push: 'end' });

    Notifications.instrument('e.started', { }, { @order.push: 'block' });

    expect(@order).to.eq(['start', 'block', 'end']);
  }

  context 'when only the start event has a subscriber', :order<defined>, {
    it 'notifies the start event with the payload', {
      my @got;
      Notifications.subscribe('e.only-start.start', -> %p { @got.push: %p });
      Notifications.instrument('e.only-start', { tag => 'y' }, { 1 });
      expect(@got[0]<tag>).to.eq('y');
    }

    it 'leaves the duration out of the start payload', {
      my @got;
      Notifications.subscribe('e.only-start.start', -> %p { @got.push: %p });
      Notifications.instrument('e.only-start', { }, { 1 });
      expect(@got[0]<duration>:exists).to.be-falsy;
    }
  }

  it 'runs the block when nothing is subscribed', {
    expect(Notifications.instrument('nobody', { }, { 7 })).to.eq(7);
  }

  it 'returns a list result decontainerized so callers iterate the rows', {
    Notifications.subscribe('e.rows', -> %p { });

    my $count = 0;
    $count++ for Notifications.instrument('e.rows', { }, { (1, 2, 3) });

    expect($count).to.eq(3);
  }
}

describe 'QueryLogs tagging', :order<defined>, {
  before-each { reset-instrumentation }
  after-each  { reset-instrumentation }

  it 'produces no comment while disabled', {
    expect(QueryLogs.comment).to.eq('');
  }

  it 'builds a comment from the tags', {
    QueryLogs.enable;
    QueryLogs.set-tags([application => 'myapp', controller => 'users']);
    expect(QueryLogs.comment).to.eq('/*application:myapp,controller:users*/');
  }

  it 'resolves a callable tag value', {
    QueryLogs.enable;
    QueryLogs.add-tag('dyn', { 'live' });
    expect(QueryLogs.comment).to.eq('/*dyn:live*/');
  }

  it 'strips a comment terminator from a value', {
    QueryLogs.enable;
    QueryLogs.set-tags([bad => 'a*/b']);
    expect(QueryLogs.comment).to.eq('/*bad:ab*/');
  }
}

describe 'LogSubscriber classification', :order<defined>, {
  before-each { reset-instrumentation }
  after-each  { reset-instrumentation }

  it 'flags a duration at or above the threshold as slow', {
    LogSubscriber.attach(slow-threshold => 0.1);
    expect(LogSubscriber.is-slow(0.5)).to.be-truthy;
  }

  it 'does not flag a duration below the threshold', {
    LogSubscriber.attach(slow-threshold => 0.1);
    expect(LogSubscriber.is-slow(0.01)).to.be-falsy;
  }

  it 'does not flag anything when no threshold is set', {
    expect(LogSubscriber.is-slow(9.9)).to.be-falsy;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'database-backed instrumentation', :order<defined>, {
  before-each { reset-instrumentation }
  after-each  { reset-instrumentation }

  context 'sql events', :order<defined>, {
    it 'fires sql.active_record for an executed query', {
      my @sql;
      Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p });
      $adapter.exec('SELECT 1');
      expect(@sql.first({ .<sql> eq 'SELECT 1' }).defined).to.be-truthy;
    }

    it 'carries a numeric duration on the sql event', {
      my @sql;
      Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p });
      $adapter.exec('SELECT 1');
      expect(@sql.first({ .<sql> eq 'SELECT 1' })<duration> ~~ Numeric).to.be-truthy;
    }

    it 'fires sql.active_record.start for an executed query', {
      my @start;
      Notifications.subscribe('sql.active_record.start', -> %p { @start.push: %p });
      $adapter.exec('SELECT 1');
      expect(@start.first({ .<sql> eq 'SELECT 1' }).defined).to.be-truthy;
    }

    it 'carries the statement name on the sql start event', {
      my @start;
      Notifications.subscribe('sql.active_record.start', -> %p { @start.push: %p });
      $adapter.exec('SELECT 1');
      expect(@start.first({ .<sql> eq 'SELECT 1' })<name>.defined).to.be-truthy;
    }

    it 'leaves the duration out of the sql start event', {
      my @start;
      Notifications.subscribe('sql.active_record.start', -> %p { @start.push: %p });
      Notifications.subscribe('sql.active_record', -> %p { });
      $adapter.exec('SELECT 1');
      expect(@start.first({ .<sql> eq 'SELECT 1' })<duration>:exists).to.be-falsy;
    }

    it 'fires sql.active_record.start before sql.active_record', {
      my @order;
      Notifications.subscribe('sql.active_record.start', -> %p { @order.push: 'start' if %p<sql> eq 'SELECT 1' });
      Notifications.subscribe('sql.active_record', -> %p { @order.push: 'end' if %p<sql> eq 'SELECT 1' });
      $adapter.exec('SELECT 1');
      expect(@order).to.eq(['start', 'end']);
    }

    it 'marks a cache hit as cached', {
      my $conn = DB.shared.build-connection;
      $conn.enable-query-cache;
      LEAVE $conn.disconnect;
      my @sql;
      Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p });
      $conn.exec('SELECT 1');
      $conn.exec('SELECT 1');
      expect(@sql.grep({ .<cached> }).elems).to.eq(1);
    }
  }

  context 'query-log tags', :order<defined>, {
    it 'appends the comment to the executed sql', {
      QueryLogs.enable;
      QueryLogs.set-tags([app => 'instr']);
      my @sql;
      Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p });
      $adapter.exec('SELECT 1');
      expect(@sql.grep({ .<sql>.contains('/*app:instr*/') }).elems).to.be-truthy;
    }
  }

  context 'instantiation events', :order<defined>, {
    before-each {
      InstrWidget.destroy-all;
      InstrWidget.create({ name => 'a' });
      InstrWidget.create({ name => 'b' });
    }

    it 'reports the class name and record count', {
      my @inst;
      Notifications.subscribe('instantiation.active_record', -> %p { @inst.push: %p });
      InstrWidget.all.perform;
      aggregate-failures {
        expect(@inst[0]<record-count>).to.eq(2);
        expect(@inst[0]<class-name>).to.match(/InstrWidget/);
      }
    }
  }

  context 'transaction events', :order<defined>, {
    it 'fires start_transaction then transaction(commit) on commit', {
      my @tx;
      Notifications.subscribe('start_transaction.active_record', -> %p { @tx.push: 'start' });
      Notifications.subscribe('transaction.active_record', -> %p { @tx.push: %p<outcome> });
      DB.shared.transaction({ InstrWidget.create({ name => 'c' }) });
      expect(@tx).to.eq(['start', 'commit']);
    }

    it 'fires transaction(rollback) on a rolled-back transaction', {
      my @tx;
      Notifications.subscribe('transaction.active_record', -> %p { @tx.push: %p<outcome> });
      DB.shared.transaction({ InstrWidget.create({ name => 'd' }); die X::Rollback.new });
      expect(@tx).to.eq(['rollback']);
    }
  }

  context 'slow-query logging', :order<defined>, {
    it 'flags a query over the slow threshold', {
      my @slow;
      LogSubscriber.attach(slow-threshold => 0, sink => -> %p, :$slow { @slow.push: $slow });
      $adapter.exec('SELECT 1');
      expect(@slow.grep({ $_ }).elems).to.be-truthy;
    }

    it 'logs a non-slow query when log-all is on', {
      my @all;
      LogSubscriber.attach(slow-threshold => 999, log-all => True, sink => -> %p, :$slow { @all.push: $slow });
      $adapter.exec('SELECT 1');
      expect(@all[0]).to.be-falsy;
    }
  }
}
