use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Schema::Field;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

describe 'SqliteAdapter direct integration', {
  if !$has-sqlite {
    pending 'DBDish::SQLite not installed in this environment';
  } else {
    it 'connects to :memory: from BUILD', {
      my $sqlite = SqliteAdapter.new(database => ':memory:');
      expect($sqlite.is-connected).to.be-truthy;
    }

    it 'exposes a non-empty sqlite_version()', {
      my $sqlite = SqliteAdapter.new(database => ':memory:');
      expect($sqlite.sqlite-version.chars).to.be-greater-than(0);
    }

    it 'returns ? from bind-placeholder for n=1', {
      my $sqlite = SqliteAdapter.new(database => ':memory:');
      expect($sqlite.bind-placeholder(1)).to.eq('?');
    }

    it 'returns ? from bind-placeholder for n=7', {
      my $sqlite = SqliteAdapter.new(database => ':memory:');
      expect($sqlite.bind-placeholder(7)).to.eq('?');
    }
  }
}

describe 'SqliteAdapter ddl + introspection', {
  if !$has-sqlite {
    pending 'DBDish::SQLite not installed in this environment';
  } else {
    my $sqlite;
    my %types-by-name;

    before-each {
      $sqlite = SqliteAdapter.new(database => ':memory:');
      $sqlite.ddl-create-table('widgets', [
        name      => { :string, limit => 64 },
        qty       => { :integer, default => 0 },
        active    => { :boolean, default => True },
        body      => { :text },
      ]);
      $sqlite.ddl-add-timestamps('widgets');

      my @fields = $sqlite.get-fields(table => 'widgets');
      %types-by-name = @fields.map({ $_[0] => $_[1] });
    }

    after-each {
      $sqlite.disconnect if $sqlite && $sqlite.is-connected;
    }

    it 'sees the id column via introspection', {
      expect(%types-by-name<id>:exists).to.be-truthy;
    }

    it 'normalizes id to integer', {
      expect(%types-by-name<id>).to.eq('integer');
    }

    it 'emits a string column as text', {
      expect(%types-by-name<name>).to.eq('text');
    }

    it 'emits an integer column as integer', {
      expect(%types-by-name<qty>).to.eq('integer');
    }

    it 'labels a boolean column as boolean', {
      expect(%types-by-name<active>).to.eq('boolean');
    }

    it 'labels a timestamp column as datetime', {
      expect(%types-by-name<created_at>).to.eq('datetime');
    }

    it 'lists the new table via get-table-names', {
      my @tables = $sqlite.get-table-names;
      expect(('widgets' (elem) @tables).so).to.be-truthy;
    }

    it 'filters internal sqlite_% tables out of get-table-names', {
      my @tables = $sqlite.get-table-names;
      expect(('sqlite_sequence' (elem) @tables).so).to.be-falsy;
    }
  }
}

describe 'SqliteAdapter build-insert / exec-stmt', {
  if !$has-sqlite {
    pending 'DBDish::SQLite not installed in this environment';
  } else {
    my $sqlite;
    my $id1;
    my $id2;
    my @field-objs;

    before-each {
      $sqlite = SqliteAdapter.new(database => ':memory:');
      $sqlite.ddl-create-table('widgets', [
        name      => { :string, limit => 64 },
        qty       => { :integer, default => 0 },
        active    => { :boolean, default => True },
        body      => { :text },
      ]);
      $sqlite.ddl-add-timestamps('widgets');

      my %types = name => 'TEXT', qty => 'INTEGER', active => 'INTEGER', body => 'TEXT';

      my $stmt = $sqlite.build-insert(
        table => 'widgets',
        attrs => { name => 'alpha', qty => 3, active => True, body => 'lorem' },
        :%types,
      );
      my $rows = $sqlite.exec-stmt($stmt);
      $id1 = $sqlite.sqlite-version ge '3.35.0' && $rows.elems
        ?? $rows[0][0].Int
        !! $sqlite.exec('SELECT last_insert_rowid()')[0][0].Int;

      my $stmt2 = $sqlite.build-insert(
        table => 'widgets',
        attrs => { name => 'beta', qty => 7, active => False, body => 'ipsum' },
        :%types,
      );
      my $rows2 = $sqlite.exec-stmt($stmt2);
      $id2 = $sqlite.sqlite-version ge '3.35.0' && $rows2.elems
        ?? $rows2[0][0].Int
        !! $sqlite.exec('SELECT last_insert_rowid()')[0][0].Int;

      @field-objs = $sqlite.get-fields(table => 'widgets').map({
        Field.new(name => $_[0], type => $_[1]);
      });
    }

    after-each {
      $sqlite.disconnect if $sqlite && $sqlite.is-connected;
    }

    it 'uses ? placeholders rather than $N in INSERT', {
      my %types = name => 'TEXT', qty => 'INTEGER', active => 'INTEGER', body => 'TEXT';
      my $stmt = $sqlite.build-insert(
        table => 'widgets',
        attrs => { name => 'check', qty => 1, active => True, body => 'x' },
        :%types,
      );
      expect($stmt.sql.contains('?')).to.be-truthy;
    }

    it 'assigns a positive surrogate id on first insert', {
      expect($id1).to.be-greater-than(0);
    }

    it 'advances AUTOINCREMENT by one', {
      expect($id2).to.eq($id1 + 1);
    }

    it 'reads INTEGER+boolean back as Bool', {
      my $row = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<active>).to.be-a(Bool);
    }

    it 'preserves True on round-trip', {
      my $row = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<active>).to.eq(True);
    }

    it 'preserves an integer round-trip as Int value', {
      my $row = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<qty>).to.eq(3);
    }

    it 'preserves a string round-trip', {
      my $row = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<name>).to.eq('alpha');
    }

    it 'preserves False on round-trip (no longer mangled to "")', {
      my $row2 = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id2 },
      );
      expect($row2<active>).to.eq(False);
    }

    it 'coerces CURRENT_TIMESTAMP TEXT default to DateTime', {
      my $row = $sqlite.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<created_at>).to.be-a(DateTime);
    }

    it 'binds value plus id (2 binds) in build-update', {
      my $now = DateTime.new('2026-05-09T12:34:56Z');
      my $dt-stmt = SqliteAdapter.new(database => ':memory:').build-update(
        :table('widgets'),
        :id($id1),
        attrs => { created_at => $now },
        types => { created_at => 'TEXT' },
      );
      expect($dt-stmt.binds.elems).to.eq(2);
    }

    it 'reports the affected row count from delete-records', {
      my $deleted = $sqlite.delete-records(table => 'widgets', where => { id => $id1 });
      expect($deleted).to.eq(1);
    }

    it 'leaves one row remaining after deleting id1', {
      $sqlite.delete-records(table => 'widgets', where => { id => $id1 });
      my @remaining = $sqlite.get-records(
        table  => 'widgets',
        fields => @field-objs,
      );
      expect(@remaining.elems).to.eq(1);
    }
  }
}

describe 'SqliteAdapter disconnect / reconnect', {
  if !$has-sqlite {
    pending 'DBDish::SQLite not installed in this environment';
  } else {
    my $sqlite;

    before-each {
      $sqlite = SqliteAdapter.new(database => ':memory:');
    }

    after-each {
      $sqlite.disconnect if $sqlite && $sqlite.is-connected;
    }

    it 'returns truthy from disconnect when a handle existed', {
      expect($sqlite.disconnect).to.be-truthy;
    }

    it 'reports false from is-connected after disconnect', {
      $sqlite.disconnect;
      expect($sqlite.is-connected).to.be-falsy;
    }

    it 're-establishes the connection on reconnect', {
      $sqlite.disconnect;
      $sqlite.reconnect;
      expect($sqlite.is-connected).to.be-truthy;
    }
  }
}
