use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS ol_notes');
  $adapter.ddl-create-table('ol_notes', [
    title        => { :string, limit => 64 },
    views        => { :integer, default => 0 },
    lock_version => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('ol_notes');
}

class OlNote is Model {
  method table-name { 'ol_notes' }
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS ol_notes');
    try $adapter.exec('DROP TABLE IF EXISTS ol_widgets');
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'optimistic locking', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    OlNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'detects the lock_version column', {
    expect(OlNote.new(:id(0)).is-locking-enabled).to.be-truthy;
  }

  it 'starts a new record at lock_version 0', {
    my $a = OlNote.create({ title => 'one' });
    expect($a.lock_version).to.eq(0);
  }

  context 'successive saves', {
    it 'returns True on first update', {
      my $a = OlNote.create({ title => 'one' });
      $a.title = 'two';
      expect($a.save).to.be-truthy;
    }

    it 'bumps lock_version to 1 after first update', {
      my $a = OlNote.create({ title => 'one' });
      $a.title = 'two';
      $a.save;
      expect($a.lock_version).to.eq(1);
    }

    it 'persists lock_version to DB', {
      my $a = OlNote.create({ title => 'one' });
      $a.title = 'two';
      $a.save;
      my $fresh = OlNote.find($a.id);
      expect($fresh.lock_version).to.eq(1);
    }

    it 'bumps lock_version to 2 after a second update', {
      my $a = OlNote.create({ title => 'one' });
      $a.title = 'two';
      $a.save;
      $a.title = 'three';
      $a.save;
      expect($a.lock_version).to.eq(2);
    }
  }

  context 'stale write rejection', {
    it 'allows the first writer to save', {
      my $a = OlNote.create({ title => 'one' });
      my $stale = OlNote.find($a.id);
      $a.title = 'winner';
      expect($a.save).to.be-truthy;
    }

    it 'bumps lock_version on the first writer', {
      my $a = OlNote.create({ title => 'one' });
      $a.title = 'winner';
      $a.save;
      expect($a.lock_version).to.eq(1);
    }

    it 'raises X::StaleObjectError on the stale writer', {
      my $a = OlNote.create({ title => 'one' });
      my $stale = OlNote.find($a.id);
      $a.title = 'winner';
      $a.save;
      $stale.title = 'loser';
      expect({ $stale.save }).to.raise-error(X::StaleObjectError);
    }

    it 'recovers via reload + save', {
      my $a = OlNote.create({ title => 'one' });
      my $stale = OlNote.find($a.id);
      $a.title = 'winner';
      $a.save;
      $stale.title = 'loser';
      try { $stale.save };
      $stale.reload;
      expect($stale.title).to.eq('winner');
    }

    it 'allows save after reload', {
      my $a = OlNote.create({ title => 'one' });
      my $stale = OlNote.find($a.id);
      $a.title = 'winner';
      $a.save;
      $stale.title = 'loser';
      try { $stale.save };
      $stale.reload;
      $stale.title = 'after reload';
      expect($stale.save).to.be-truthy;
    }
  }

  context 'update-all', {
    it 'returns affected row count', {
      OlNote.create({ title => 'a' });
      OlNote.create({ title => 'b' });
      expect(OlNote.update-all({ views => 5 })).to.eq(2);
    }

    it 'auto-bumps lock_version on every affected row', {
      OlNote.create({ title => 'a' });
      OlNote.create({ title => 'b' });
      OlNote.update-all({ views => 5 });
      expect(OlNote.where({ lock_version => 1 }).count).to.eq(2);
    }

    it 'marks in-memory records stale after a scoped update-all', {
      my $a = OlNote.create({ title => 'a' });
      my $stale = OlNote.find($a.id);
      OlNote.where({ id => $a.id }).update-all({ views => 99 });
      $stale.title = 'never';
      expect({ $stale.save }).to.raise-error(X::StaleObjectError);
    }

    it 'honors an explicit lock_version in update-all (no double bump)', {
      my $a = OlNote.create({ title => 'a' });
      OlNote.where({ id => $a.id }).update-all({ lock_version => 42 });
      my $fresh = OlNote.find($a.id);
      expect($fresh.lock_version).to.eq(42);
    }
  }

  context 'update-counters', {
    it 'increments the counter', {
      my $a = OlNote.create({ title => 'a' });
      OlNote.where({ id => $a.id }).update-counters(views => 10);
      my $fresh = OlNote.find($a.id);
      expect($fresh.views).to.eq(10);
    }

    it 'auto-bumps lock_version', {
      my $a = OlNote.create({ title => 'a' });
      OlNote.where({ id => $a.id }).update-counters(views => 10);
      my $fresh = OlNote.find($a.id);
      expect($fresh.lock_version).to.eq(1);
    }
  }

  context 'after a stale failure', {
    it 'reverts the in-memory lock_version on the stale instance', {
      my $a = OlNote.create({ title => 'a' });
      my $stale = OlNote.find($a.id);
      $a.title = 'changed';
      $a.save;
      $stale.title = 'attempted';
      try { $stale.save };
      expect($stale.lock_version).to.eq(1);
    }

    it 'lets the winning writer keep saving', {
      my $a = OlNote.create({ title => 'a' });
      my $stale = OlNote.find($a.id);
      $a.title = 'changed';
      $a.save;
      $stale.title = 'attempted';
      try { $stale.save };
      $a.title = 'second change';
      expect($a.save).to.be-truthy;
    }

    it 'continues to bump lock_version on the winning writer', {
      my $a = OlNote.create({ title => 'a' });
      my $stale = OlNote.find($a.id);
      $a.title = 'changed';
      $a.save;
      $stale.title = 'attempted';
      try { $stale.save };
      $a.title = 'second change';
      $a.save;
      expect($a.lock_version).to.eq(2);
    }
  }

  context 'tables without lock_version', {
    before-each {
      next unless $has-db;
      $adapter.exec('DROP TABLE IF EXISTS ol_widgets');
      $adapter.ddl-create-table('ol_widgets', [
        name => { :string, limit => 64 },
      ]);
    }

    after-each {
      $adapter.exec('DROP TABLE IF EXISTS ol_widgets') if $has-db;
    }

    it 'reports is-locking-enabled as False', {
      my class OlWidget is Model { method table-name { 'ol_widgets' } }
      expect(OlWidget.new(:id(0)).is-locking-enabled).to.be-falsy;
    }

    it 'still allows save', {
      my class OlWidget is Model { method table-name { 'ol_widgets' } }
      my $w = OlWidget.create({ name => 'no-lock' });
      $w.name = 'updated';
      expect($w.save).to.be-truthy;
    }
  }
}
