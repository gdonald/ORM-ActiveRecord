use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS sup_notes');
  $adapter.ddl-create-table('sup_notes', [
    title => { :string, limit => 64 },
    views => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('sup_notes');

  $adapter.exec('DROP TABLE IF EXISTS sup_memos');
  $adapter.ddl-create-table('sup_memos', [
    title => { :string, limit => 64 },
  ]);
  $adapter.ddl-add-timestamps('sup_memos');
}

class SupNote is Model {
  method table-name { 'sup_notes' }
}

class SupMemo is Model {
  method table-name { 'sup_memos' }
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS sup_notes');
    try $adapter.exec('DROP TABLE IF EXISTS sup_memos');
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'Model.suppress { create }', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    SupNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'does not persist the row', {
    SupNote.suppress({ SupNote.create({ title => 'ghost' }) });
    expect(SupNote.count).to.eq(0);
  }

  it 'still returns an instance', {
    my $obj;
    SupNote.suppress({ $obj = SupNote.create({ title => 'ghost' }) });
    expect($obj.defined).to.be-truthy;
  }

  it 'leaves the requested attrs on the in-memory record', {
    my $obj;
    SupNote.suppress({ $obj = SupNote.create({ title => 'ghost' }) });
    expect($obj.title).to.eq('ghost');
  }

  it 'leaves id at 0 because save was suppressed', {
    my $obj;
    SupNote.suppress({ $obj = SupNote.create({ title => 'ghost' }) });
    expect($obj.id).to.eq(0);
  }
}

group 'Model.suppress { .save }', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    SupNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'returns True from save', {
    my $saved-ok;
    SupNote.suppress({
      my $obj = SupNote.new(:id(0), :record({ attrs => { title => 'never' } }));
      $saved-ok = $obj.save;
    });
    expect($saved-ok).to.be-truthy;
  }

  it 'writes nothing to the DB', {
    SupNote.suppress({
      my $obj = SupNote.new(:id(0), :record({ attrs => { title => 'never' } }));
      $obj.save;
    });
    expect(SupNote.count).to.eq(0);
  }
}

group 'after a suppress block', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    SupNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'persistence resumes', {
    SupNote.suppress({ SupNote.create({ title => 'x' }) });
    SupNote.create({ title => 'after' });
    expect(SupNote.count).to.eq(1);
  }

  it 'only the post-suppress row is present', {
    SupNote.suppress({ SupNote.create({ title => 'x' }) });
    SupNote.create({ title => 'after' });
    expect(SupNote.first.title).to.eq('after');
  }
}

group 'is-suppressed flag', {
  it 'is False outside the block', {
    expect(SupNote.is-suppressed).to.be-falsy;
  }

  it 'is True inside the block', {
    my $inside;
    SupNote.suppress({ $inside = SupNote.is-suppressed });
    expect($inside).to.be-truthy;
  }

  it 'clears after the block', {
    SupNote.suppress(sub {});
    expect(SupNote.is-suppressed).to.be-falsy;
  }
}

group 'nested suppression', {
  it 'flags suppression in the outer block', {
    my $outer;
    SupNote.suppress({ $outer = SupNote.is-suppressed });
    expect($outer).to.be-truthy;
  }

  it 'flags suppression in the inner block', {
    my $inner;
    SupNote.suppress({
      SupNote.suppress({ $inner = SupNote.is-suppressed });
    });
    expect($inner).to.be-truthy;
  }

  it 'outer block stays suppressed after inner returns', {
    my $outer-after-inner;
    SupNote.suppress({
      SupNote.suppress(sub {});
      $outer-after-inner = SupNote.is-suppressed;
    });
    expect($outer-after-inner).to.be-truthy;
  }
}

group 'exception inside suppress', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    SupNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'clears the flag when the block throws', {
    try { SupNote.suppress({ die 'boom' }) };
    expect(SupNote.is-suppressed).to.be-falsy;
  }

  it 'allows persistence afterward', {
    try { SupNote.suppress({ die 'boom' }) };
    SupNote.create({ title => 'live' });
    expect(SupNote.count).to.eq(1);
  }
}

group 'update under suppress', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    SupNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'leaves the title untouched on disk', {
    my $obj = SupNote.create({ title => 'orig', views => 1 });
    SupNote.suppress({ $obj.update({ title => 'changed', views => 99 }) });
    expect(SupNote.find($obj.id).title).to.eq('orig');
  }

  it 'leaves the numeric column untouched', {
    my $obj = SupNote.create({ title => 'orig', views => 1 });
    SupNote.suppress({ $obj.update({ title => 'changed', views => 99 }) });
    expect(SupNote.find($obj.id).views).to.eq(1);
  }
}

group 'sibling-class isolation', {
  before-each {
    if $has-db {
      try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
      SupNote.destroy-all;
      SupMemo.destroy-all;
    }
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'SupNote.suppress blocks SupNote saves', {
    SupNote.suppress({
      SupNote.create({ title => 'a' });
      SupMemo.create({ title => 'b' });
    });
    expect(SupNote.count).to.eq(0);
  }

  it 'SupNote.suppress does not block SupMemo saves', {
    SupNote.suppress({
      SupNote.create({ title => 'a' });
      SupMemo.create({ title => 'b' });
    });
    expect(SupMemo.count).to.eq(1);
  }
}
