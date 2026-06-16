use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Schema::Cache;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub adapter-kind(--> Str) {
  return 'none' without $adapter;
  given $adapter.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

my $kind      = adapter-kind();
my $is-pg     = $kind eq 'pg';
my $is-mysql  = $kind eq 'mysql';
my $is-sqlite = $kind eq 'sqlite';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub cleanup-tables {
  for < _si_things _si_widgets > -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

sub index-columns(Str:D $table) {
  $adapter.get-indexes(:$table).map({ .<columns>.list }).flat.list;
}

sub constraint-types(Str:D $table) {
  $adapter.get-constraints(:$table).map(*.<type>).list;
}

# `_si_widget` pluralises to `_si_widgets`, so the reference FK targets it.
class CreateWidgets is Migration {
  method change {
    self.create-table: '_si_widgets', [ name => { :string, limit => 32 } ];
  }
}

class CreateThings is Migration {
  method change {
    self.create-table: '_si_things', [
      _si_widget => { :reference },
      token      => { :string, limit => 32, unique => True },
      val        => { :integer },
    ];
    self.add-index: '_si_things', :val;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

my &pg-it     = $is-pg     ?? &it !! &xit;
my &mysql-it  = $is-mysql  ?? &it !! &xit;
my &sqlite-it = $is-sqlite ?? &it !! &xit;

my $cache-path = $*TMPDIR.add('ar-schema-cache-spec.json').Str;

group 'schema introspection', :order<defined>, {
  before-all {
    cleanup-tables;
    CreateWidgets.new.up;
    CreateThings.new.up;
    # SQLite only records a table in sqlite_sequence after its first insert.
    $adapter.exec(q{INSERT INTO _si_things (token, val) VALUES ('t1', 1)});
  }
  after-all {
    cleanup-tables;
    try { $cache-path.IO.unlink }
  }

  context 'index introspection', {
    it 'reports the column-covering index added to a table', {
      expect('val' (elem) index-columns('_si_things')).to.be-truthy;
    }

    it 'reports whether an index is unique', {
      my @uniques = $adapter.get-indexes(table => '_si_things').grep(*.<unique>);
      expect(@uniques.elems > 0).to.be-truthy;
    }
  }

  context 'constraint introspection', {
    it 'reports the foreign key', {
      expect('foreign-key' (elem) constraint-types('_si_things')).to.be-truthy;
    }

    it 'reports the unique constraint', {
      expect('unique' (elem) constraint-types('_si_things')).to.be-truthy;
    }

    it 'reports the primary key', {
      expect('primary-key' (elem) constraint-types('_si_things')).to.be-truthy;
    }
  }

  context 'sequence introspection', {
    pg-it 'lists the serial sequence (PostgreSQL)', {
      expect($adapter.get-sequences.grep({ .contains('_si_things') }).elems > 0).to.be-truthy;
    }

    sqlite-it 'lists the autoincrement table (SQLite)', {
      expect('_si_things' (elem) $adapter.get-sequences).to.be-truthy;
    }

    mysql-it 'has no sequences (MySQL)', {
      expect($adapter.get-sequences.elems).to.eq(0);
    }
  }

  context 'schema cache', :order<defined>, {
    it 'round-trips table names through serialize/deserialize', {
      my $json   = SchemaCache.new(adapter => $adapter).serialize;
      my $loaded = SchemaCache.new.deserialize($json);
      expect('_si_things' (elem) $loaded.table-names).to.be-truthy;
    }

    it 'caches a table\'s columns', {
      my $json   = SchemaCache.new(adapter => $adapter).serialize;
      my $loaded = SchemaCache.new.deserialize($json);
      expect('val' (elem) $loaded.columns-for('_si_things').map(*<name>)).to.be-truthy;
    }

    it 'round-trips through a dumped file', {
      SchemaCache.new(adapter => $adapter).dump(path => $cache-path);
      my $loaded = SchemaCache.new.load(path => $cache-path);
      expect('_si_things' (elem) $loaded.table-names).to.be-truthy;
    }

    it 'round-trips through a YAML file', {
      my $yaml-path = $cache-path ~ '.yml';
      SchemaCache.new(adapter => $adapter).dump-yaml(path => $yaml-path);
      my $loaded = SchemaCache.new.load-yaml(path => $yaml-path);
      LEAVE { try { $yaml-path.IO.unlink } }
      expect('_si_things' (elem) $loaded.table-names).to.be-truthy;
    }
  }
}
