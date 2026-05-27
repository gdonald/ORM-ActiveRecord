use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS tcb_widgets');
  $adapter.ddl-create-table('tcb_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('tcb_widgets');
}

my @events;

class TcbWidget is Model {
  method table-name { 'tcb_widgets' }

  submethod BUILD {
    self.after-commit:         -> { @events.push: 'commit:'         ~ (self.name // '') };
    self.after-rollback:       -> { @events.push: 'rollback:'       ~ (self.name // '') };
    self.after-create-commit:  -> { @events.push: 'create-commit:'  ~ (self.name // '') };
    self.after-update-commit:  -> { @events.push: 'update-commit:'  ~ (self.name // '') };
    self.after-destroy-commit: -> { @events.push: 'destroy-commit:' ~ (self.name // '') };
    self.after-save-commit:    -> { @events.push: 'save-commit:'    ~ (self.name // '') };
  }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS tcb_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'transactional callbacks', {
  before-each {
    if $has-db {
      try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
      TcbWidget.destroy-all;
      @events = ();
    }
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  context 'create inside a committed transaction', {
    before-each {
      DB.shared.transaction({ TcbWidget.create({ name => 'a', qty => 1 }) });
    }

    it 'fires after-commit', {
      expect(@events.grep('commit:a').elems).to.eq(1);
    }

    it 'fires after-create-commit', {
      expect(@events.grep('create-commit:a').elems).to.eq(1);
    }

    it 'fires after-save-commit', {
      expect(@events.grep('save-commit:a').elems).to.eq(1);
    }

    it 'does not fire after-update-commit', {
      expect(@events.grep('update-commit:a').elems).to.eq(0);
    }

    it 'does not fire after-rollback', {
      expect(@events.grep('rollback:a').elems).to.eq(0);
    }
  }

  context 'rolled-back transaction', {
    before-each {
      try {
        DB.shared.transaction({
          TcbWidget.create({ name => 'b', qty => 1 });
          die X::Rollback.new;
        });
      };
    }

    it 'rollback path completes', {
      expect({
        DB.shared.transaction({
          TcbWidget.create({ name => 'b2', qty => 1 });
          die X::Rollback.new;
        });
      }).not.to.raise-error;
    }

    it 'does not fire after-commit', {
      expect(@events.grep('commit:b').elems).to.eq(0);
    }

    it 'does not fire after-create-commit', {
      expect(@events.grep('create-commit:b').elems).to.eq(0);
    }

    it 'fires after-rollback', {
      expect(@events.grep('rollback:b').elems).to.eq(1);
    }
  }

  context 'update inside a committed transaction', {
    before-each {
      my $w = TcbWidget.create({ name => 'c', qty => 1 });
      @events = ();
      DB.shared.transaction({
        $w.qty = 99;
        $w.save;
      });
    }

    it 'fires after-update-commit', {
      expect(@events.grep('update-commit:c').elems).to.eq(1);
    }

    it 'fires after-save-commit', {
      expect(@events.grep('save-commit:c').elems).to.eq(1);
    }

    it 'does not fire after-create-commit', {
      expect(@events.grep('create-commit:c').elems).to.eq(0);
    }

    it 'fires after-commit once', {
      expect(@events.grep('commit:c').elems).to.eq(1);
    }
  }

  context 'destroy inside a committed transaction', {
    before-each {
      my $w = TcbWidget.create({ name => 'd', qty => 1 });
      @events = ();
      DB.shared.transaction({ $w.destroy });
    }

    it 'fires after-destroy-commit', {
      expect(@events.grep('destroy-commit:d').elems).to.eq(1);
    }

    it 'does not fire after-save-commit', {
      expect(@events.grep('save-commit:d').elems).to.eq(0);
    }

    it 'fires after-commit', {
      expect(@events.grep('commit:d').elems).to.eq(1);
    }
  }

  context 'create outside any transaction', {
    before-each {
      TcbWidget.create({ name => 'e', qty => 1 });
    }

    it 'fires after-commit immediately', {
      expect(@events.grep('commit:e').elems).to.eq(1);
    }

    it 'fires after-create-commit immediately', {
      expect(@events.grep('create-commit:e').elems).to.eq(1);
    }
  }

  context 'savepoint rollback inside an outer commit', {
    before-each {
      DB.shared.transaction({
        TcbWidget.create({ name => 'outer', qty => 1 });
        try {
          DB.shared.transaction(:requires-new, {
            TcbWidget.create({ name => 'sp-doomed', qty => 9 });
            die X::Rollback.new;
          });
        };
      });
    }

    it 'fires after-rollback for the inner record', {
      expect(@events.grep('rollback:sp-doomed').elems).to.eq(1);
    }

    it 'does not fire after-commit for the inner record', {
      expect(@events.grep('commit:sp-doomed').elems).to.eq(0);
    }

    it 'still fires after-commit for the outer record', {
      expect(@events.grep('commit:outer').elems).to.eq(1);
    }
  }

  context 'two saves of the same record inside one transaction', {
    before-each {
      my $w = TcbWidget.create({ name => 'dup', qty => 1 });
      @events = ();
      DB.shared.transaction({
        $w.qty = 2;
        $w.save;
        $w.qty = 3;
        $w.save;
      });
    }

    it 'fires after-commit once', {
      expect(@events.grep('commit:dup').elems).to.eq(1);
    }

    it 'fires after-save-commit once', {
      expect(@events.grep('save-commit:dup').elems).to.eq(1);
    }
  }
}
