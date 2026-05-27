use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS pl_notes');
  $adapter.ddl-create-table('pl_notes', [
    title => { :string, limit => 64 },
    views => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('pl_notes');
}

class PlNote is Model {
  method table-name { 'pl_notes' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS pl_notes') if $has-db;
}

my $is-sqlite = $has-db && $adapter.WHAT.^name.contains('Sqlite');

my &group = $has-db ?? &describe !! &xdescribe;

group 'pessimistic locking SQL emission', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    PlNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  context 'relation .lock', {
    it 'emits FOR UPDATE (or drops it on sqlite)', {
      my $sql = PlNote.where({ id => 1 }).lock.to-sql;
      if $is-sqlite {
        expect($sql.uc.contains('FOR UPDATE')).to.be-falsy;
      } else {
        expect($sql.uc.contains('FOR UPDATE')).to.be-truthy;
      }
    }

    it 'chains from class-level Model.lock', {
      my $sql = PlNote.lock.where({ id => 1 }).to-sql;
      if $is-sqlite {
        expect($sql.uc.contains('FOR UPDATE')).to.be-falsy;
      } else {
        expect($sql.uc.contains('FOR UPDATE')).to.be-truthy;
      }
    }

    it 'emits FOR SHARE when asked', {
      my $sql = PlNote.where({ id => 1 }).lock('FOR SHARE').to-sql;
      if $is-sqlite {
        expect($sql.uc.contains('FOR SHARE')).to.be-falsy;
      } else {
        expect($sql.uc.contains('FOR SHARE')).to.be-truthy;
      }
    }

    it 'passes Postgres-specific modes through verbatim', {
      my $sql = PlNote.where({ id => 1 }).lock('FOR NO KEY UPDATE').to-sql;
      if $is-sqlite {
        expect($sql.uc.contains('FOR NO KEY UPDATE')).to.be-falsy;
      } else {
        expect($sql.uc.contains('FOR NO KEY UPDATE')).to.be-truthy;
      }
    }
  }

  context 'a plain relation', {
    it 'does not emit FOR UPDATE', {
      my $sql = PlNote.where({ id => 1 }).to-sql;
      expect($sql.uc.contains('FOR UPDATE')).to.be-falsy;
    }

    it 'does not emit FOR SHARE', {
      my $sql = PlNote.where({ id => 1 }).to-sql;
      expect($sql.uc.contains('FOR SHARE')).to.be-falsy;
    }
  }

  context 'unscope(:lock)', {
    it 'removes FOR UPDATE from the emitted SQL', {
      my $rel = PlNote.where({ id => 1 }).lock;
      $rel.unscope(:lock);
      expect($rel.to-sql.uc.contains('FOR UPDATE')).to.be-falsy;
    }
  }

  context 'clone-query', {
    it 'preserves the lock setting (or no-ops on sqlite)', {
      my $rel = PlNote.where({ id => 1 }).lock('FOR UPDATE');
      my $sql = $rel.clone-query.to-sql;
      if $is-sqlite {
        expect($sql.uc.contains('FOR UPDATE')).to.be-falsy;
      } else {
        expect($sql.uc.contains('FOR UPDATE')).to.be-truthy;
      }
    }
  }
}

group 'pessimistic locking at runtime', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    PlNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'Model.lock returns rows inside a transaction', {
    PlNote.create({ title => 'one', views => 1 });
    PlNote.create({ title => 'two', views => 2 });

    my @rows;
    PlNote.transaction({
      @rows = PlNote.lock.all;
    });
    expect(@rows.elems).to.eq(2);
  }

  context 'lock-or-die', {
    it 'returns the same instance', {
      my $a = PlNote.create({ title => 'one', views => 1 });
      PlNote.where({ id => $a.id }).update-all({ views => 99 });

      my $reloaded;
      PlNote.transaction({
        $reloaded = $a.lock-or-die;
      });
      expect($reloaded.WHICH).to.eq($a.WHICH);
    }

    it 'refreshes attrs from the DB', {
      my $a = PlNote.create({ title => 'one', views => 1 });
      PlNote.where({ id => $a.id }).update-all({ views => 99 });

      PlNote.transaction({
        $a.lock-or-die;
      });
      expect($a.views).to.eq(99);
    }

    it 'raises when the row no longer exists', {
      my $a = PlNote.create({ title => 'gone' });
      $a.delete;
      expect({ $a.lock-or-die }).to.raise-error(Exception);
    }

    it 'refuses readonly records', {
      my $a = PlNote.create({ title => 'a' });
      $a.make-readonly;
      expect({ $a.lock-or-die }).to.raise-error(X::ReadOnlyRecord);
    }
  }

  context 'with-lock { ... }', {
    it 'runs the block inside a transaction', {
      my $a = PlNote.create({ title => 'init', views => 0 });
      PlNote.where({ id => $a.id }).update-all({ views => 7 });

      my $saw-txn = False;
      $a.with-lock(-> $rec { $saw-txn = DB.shared.is-in-transaction });
      expect($saw-txn).to.be-truthy;
    }

    it 'yields the freshly-locked record', {
      my $a = PlNote.create({ title => 'init', views => 0 });
      PlNote.where({ id => $a.id }).update-all({ views => 7 });

      my $saw-views;
      $a.with-lock(-> $rec { $saw-views = $rec.views });
      expect($saw-views).to.eq(7);
    }

    it 'commits when the block returns normally', {
      my $a = PlNote.create({ title => 'before' });
      $a.with-lock({ $a.update({ title => 'after' }) });
      expect(PlNote.find($a.id).title).to.eq('after');
    }

    it 'propagates exceptions and rolls back', {
      my $a = PlNote.create({ title => 'before' });
      expect({
        $a.with-lock({
          $a.update({ title => 'mid' });
          die 'boom';
        });
      }).to.raise-error;
    }

    it 'rollback reverts the update', {
      my $a = PlNote.create({ title => 'before' });
      try {
        $a.with-lock({
          $a.update({ title => 'mid' });
          die 'boom';
        });
      };
      expect(PlNote.find($a.id).title).to.eq('before');
    }
  }
}
