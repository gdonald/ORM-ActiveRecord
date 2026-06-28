use lib 'lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::DbTasks;
use ORM::ActiveRecord::Schema::Cache;

%*ENV<DISABLE-SQL-LOG> = True;

sub fresh(--> Hash) {
  my $st     = "{$*PID}-{(now * 1e6).Int}";
  my $token  = $st.subst('-', '_', :g);
  my $dbfile = $*TMPDIR.add("schema-spec-$st.sqlite3").Str;
  my $migdir = $*TMPDIR.add("schema-spec-mig-$st");
  my $schema = $*TMPDIR.add("schema-spec-$st.raku").Str;
  my $struct = $*TMPDIR.add("structure-spec-$st.sql").Str;
  my $cache  = $*TMPDIR.add("schema-cache-spec-$st.yml").Str;

  $migdir.mkdir;
  $migdir.add('001-create-people.raku').spurt: qq:to/RAKU/;
  use ORM::ActiveRecord::Schema::Migration;
  class People_$token is Migration \{
    method up \{
      self.create-table: 'people', [ name => \{ :string, limit => 32 \}, age => \{ :integer \} ];
      self.add-index: 'people', 'name';
    \}
    method down \{ self.drop-table: 'people' \}
  \}
  RAKU

  $migdir.add('002-create-pets.raku').spurt: qq:to/RAKU/;
  use ORM::ActiveRecord::Schema::Migration;
  class Pets_$token is Migration \{
    method up \{ self.create-table: 'pets', [ name => \{ :string, limit => 32 \} ] \}
    method down \{ self.drop-table: 'pets' \}
  \}
  RAKU

  $migdir.add('003-create-toys.raku').spurt: qq:to/RAKU/;
  use ORM::ActiveRecord::Schema::Migration;
  class Toys_$token is Migration \{
    method up \{
      self.create-table: 'toys', [
        name   => \{ :string, limit => 32 \},
        pet_id => \{ :integer, references => 'pets', on-delete => 'cascade' \},
      ];
    \}
    method down \{ self.drop-table: 'toys' \}
  \}
  RAKU

  %*ENV<BEHAVE_WORKER_INDEX>:delete;
  %*ENV<BEHAVE_WORKER_COUNT>:delete;
  %*ENV<DATABASE_URL> = "sqlite:$dbfile";
  DB.set-shared(Nil);

  my $null = open '/dev/null', :w;

  {
    dbfile => $dbfile, migdir => $migdir, schema => $schema, struct => $struct, cache => $cache,
    null   => $null,
    tasks  => DbTasks.new(:migration-path($migdir.Str), :out($null), :err($null)),
  };
}

sub cleanup(%env) {
  %env<null>.close;
  for <dbfile schema struct cache> -> $key {
    %env{$key}.IO.unlink if %env{$key}.IO.e;
  }
  run 'rm', '-rf', %env<migdir>.Str;
}

sub tables(Str:D $dbfile --> Set) {
  my $h = DBIish.connect('SQLite', :database($dbfile));
  LEAVE { $h.dispose if $h.defined }
  $h.execute("SELECT name FROM sqlite_master WHERE type = 'table'").allrows.map(*[0]).Set;
}

sub foreign-key-targets(Str:D $dbfile, Str:D $table --> Set) {
  my $h = DBIish.connect('SQLite', :database($dbfile));
  LEAVE { $h.dispose if $h.defined }
  $h.execute("PRAGMA foreign_key_list('$table')").allrows.map(*[2]).Set;
}

describe 'schema dump and load', {
  context 'dumping', {
    it 'writes a schema file, a structure file, and a YAML cache', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;

      %env<tasks>.schema-dump(path => %env<schema>);
      %env<tasks>.structure-dump(path => %env<struct>);
      %env<tasks>.schema-cache-dump(path => %env<cache>);

      my $dump = %env<schema>.IO.slurp;
      my $sql  = %env<struct>.IO.slurp;

      aggregate-failures {
        expect($dump.contains('class Schema is Migration')).to.be-truthy;
        expect($dump.contains("self.create-table: 'people'")).to.be-truthy;
        expect($dump.contains("self.add-index: 'people'")).to.be-truthy;
        expect($dump.contains("references => 'pets'")).to.be-truthy;
        expect($dump.contains("on-delete => 'cascade'")).to.be-truthy;
        expect($dump.contains('<001 002 003>')).to.be-truthy;
        expect($sql.contains('CREATE TABLE')).to.be-truthy;
        expect($sql.contains('INSERT INTO migrations')).to.be-truthy;
        expect('people' (elem) SchemaCache.new.load-yaml(path => %env<cache>).table-names).to.be-truthy;
      }
    }

    it 'clears the cache file', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;
      %env<tasks>.schema-cache-dump(path => %env<cache>);
      %env<tasks>.schema-cache-clear(path => %env<cache>);

      expect(%env<cache>.IO.e).to.be-falsy;
    }
  }

  context 'loading', {
    it 'purges and rebuilds the database from the dumped schema', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;
      %env<tasks>.schema-dump(path => %env<schema>);

      %env<tasks>.schema-load(path => %env<schema>);

      aggregate-failures {
        expect(tables(%env<dbfile>){'people'}).to.be-truthy;
        expect(tables(%env<dbfile>){'pets'}).to.be-truthy;
        expect(foreign-key-targets(%env<dbfile>, 'toys'){'pets'}).to.be-truthy;
        expect(%env<tasks>.version).to.eq('003');
      }
    }
  }

  context 'dumping after migrate', {
    it 'dumps outside the test environment but skips it and the opt-out', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;

      my $after = %env<migdir>.add('after.raku').Str;
      my $dev  = DbTasks.new(:migration-path(%env<migdir>.Str), :env('development'),
                             :out(%env<null>), :err(%env<null>));
      my $test = DbTasks.new(:migration-path(%env<migdir>.Str), :env('test'),
                             :out(%env<null>), :err(%env<null>));

      aggregate-failures {
        expect($dev.schema-dump-after-migrate(path => $after)).to.eq($after);
        expect($after.IO.e).to.be-truthy;

        $after.IO.unlink;
        expect($test.schema-dump-after-migrate(path => $after)).to.eq('');
        expect($after.IO.e).to.be-falsy;

        temp %*ENV<AR_NO_SCHEMA_DUMP> = '1';
        expect($dev.schema-dump-after-migrate(path => $after)).to.eq('');
        expect($after.IO.e).to.be-falsy;
      }
    }
  }
}
