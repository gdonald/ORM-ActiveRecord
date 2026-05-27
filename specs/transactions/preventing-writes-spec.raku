use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS pw_notes');
  $adapter.ddl-create-table('pw_notes', [
    title => { :string, limit => 64 },
    views => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('pw_notes');
}

class PwNote is Model {
  method table-name { 'pw_notes' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS pw_notes') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'is-preventing-writes flag', {
  it 'is False by default', {
    expect(DB.shared.is-preventing-writes).to.be-falsy;
  }

  it 'is True inside while-preventing-writes', {
    my $inside;
    DB.shared.while-preventing-writes({ $inside = DB.shared.is-preventing-writes });
    expect($inside).to.be-truthy;
  }

  it 'clears after the block', {
    DB.shared.while-preventing-writes(sub {});
    expect(DB.shared.is-preventing-writes).to.be-falsy;
  }
}

group 'is-write-sql classifier', {
  it 'classifies INSERT as a write', {
    expect($adapter.is-write-sql('INSERT INTO pw_notes(title) VALUES (?)')).to.be-truthy;
  }

  it 'classifies UPDATE as a write', {
    expect($adapter.is-write-sql('  update pw_notes set title = ? where id = 1')).to.be-truthy;
  }

  it 'classifies DELETE as a write', {
    expect($adapter.is-write-sql("DELETE FROM pw_notes WHERE id = 1")).to.be-truthy;
  }

  it 'classifies SELECT as a non-write', {
    expect($adapter.is-write-sql('SELECT * FROM pw_notes')).to.be-falsy;
  }

  it 'is not fooled by a leading comment', {
    expect($adapter.is-write-sql('  /* update */ SELECT * FROM pw_notes')).to.be-falsy;
  }
}

group 'writes inside while-preventing-writes', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    PwNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'raises ReadOnlyDatabase on INSERT', {
    expect({
      DB.shared.while-preventing-writes({
        PwNote.create({ title => 'two', views => 2 });
      });
    }).to.raise-error(X::ReadOnlyDatabase);
  }

  it 'does not actually insert', {
    PwNote.create({ title => 'one', views => 1 });
    try {
      DB.shared.while-preventing-writes({
        PwNote.create({ title => 'two', views => 2 });
      });
    };
    expect(PwNote.count).to.eq(1);
  }

  it 'allows SELECT count inside the block', {
    PwNote.create({ title => 'one', views => 1 });
    my $count;
    DB.shared.while-preventing-writes({ $count = PwNote.count });
    expect($count).to.eq(1);
  }

  it 'raises ReadOnlyDatabase on UPDATE', {
    my $a = PwNote.create({ title => 'orig', views => 1 });
    expect({
      DB.shared.while-preventing-writes({ $a.update({ views => 99 }) });
    }).to.raise-error(X::ReadOnlyDatabase);
  }

  it 'does not actually update', {
    my $a = PwNote.create({ title => 'orig', views => 1 });
    try {
      DB.shared.while-preventing-writes({ $a.update({ views => 99 }) });
    };
    expect(PwNote.find($a.id).views).to.eq(1);
  }

  it 'raises ReadOnlyDatabase on DELETE', {
    my $a = PwNote.create({ title => 'orig', views => 1 });
    expect({
      DB.shared.while-preventing-writes({ PwNote.where({ id => $a.id }).delete-all });
    }).to.raise-error(X::ReadOnlyDatabase);
  }

  it 'does not actually delete', {
    my $a = PwNote.create({ title => 'orig', views => 1 });
    try {
      DB.shared.while-preventing-writes({ PwNote.where({ id => $a.id }).delete-all });
    };
    expect(PwNote.count).to.eq(1);
  }
}

group 'block cleanup on exception', {
  before-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
    PwNote.destroy-all if $has-db;
  }

  after-each {
    try $adapter.exec('ROLLBACK') if $has-db && DB.shared.is-in-transaction;
  }

  it 'clears the flag after a thrown block', {
    try { DB.shared.while-preventing-writes({ die 'boom' }) };
    expect(DB.shared.is-preventing-writes).to.be-falsy;
  }

  it 'allows create after a thrown block', {
    try { DB.shared.while-preventing-writes({ die 'boom' }) };
    expect({ PwNote.create({ title => 'after' }) }).not.to.raise-error;
  }
}

group 'nested while-preventing-writes', {
  it 'reports True at inner depth', {
    my $inner;
    DB.shared.while-preventing-writes({
      DB.shared.while-preventing-writes({
        $inner = DB.shared.is-preventing-writes;
      });
    });
    expect($inner).to.be-truthy;
  }

  it 'preserves outer depth after inner exit', {
    my $outer-after-inner;
    DB.shared.while-preventing-writes({
      DB.shared.while-preventing-writes(sub {});
      $outer-after-inner = DB.shared.is-preventing-writes;
    });
    expect($outer-after-inner).to.be-truthy;
  }

  it 'clears both blocks at the end', {
    DB.shared.while-preventing-writes({
      DB.shared.while-preventing-writes(sub {});
    });
    expect(DB.shared.is-preventing-writes).to.be-falsy;
  }
}
