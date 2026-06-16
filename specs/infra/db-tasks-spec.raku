use lib 'lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::DbTasks;

%*ENV<DISABLE-SQL-LOG> = True;

sub migration(Str:D $table, Str:D $class) {
  qq:to/RAKU/;
  use ORM::ActiveRecord::Schema::Migration;

  class $class is Migration \{
    method up \{ self.create-table: '$table', [ name => \{ :string, limit => 32 \} ] \}
    method down \{ self.drop-table: '$table' \}
  \}
  RAKU
}

# A self-contained temp database, migration directory, and seeds file, wired to
# a DbTasks via DATABASE_URL. Each example builds its own so order never
# matters.
sub fresh(--> Hash) {
  my $stamp  = "{$*PID}-{(now * 1e6).Int}";
  my $token  = $stamp.subst('-', '_', :g);
  my $dbfile = $*TMPDIR.add("dbtasks-spec-$stamp.sqlite3").Str;
  my $migdir = $*TMPDIR.add("dbtasks-spec-mig-$stamp");
  my $seeds  = $*TMPDIR.add("dbtasks-spec-seeds-$stamp.raku").Str;

  # Class names are unique per build: each example EVALs its own migration
  # files, and a repeated class name would redeclare the symbol in GLOBAL.
  $migdir.mkdir;
  $migdir.add('001-create-widgets.raku').spurt(migration('widgets', "SpecWidgets_$token"));
  $migdir.add('002-create-gadgets.raku').spurt(migration('gadgets', "SpecGadgets_$token"));
  $migdir.add('003-create-gizmos.raku').spurt(migration('gizmos',  "SpecGizmos_$token"));

  $seeds.IO.spurt: q:to/SEEDS/;
  use ORM::ActiveRecord::DB;
  DB.shared.exec("INSERT INTO widgets (name) VALUES ('seeded')");
  SEEDS

  %*ENV<BEHAVE_WORKER_INDEX>:delete;
  %*ENV<BEHAVE_WORKER_COUNT>:delete;
  %*ENV<DATABASE_URL> = "sqlite:$dbfile";
  DB.set-shared(Nil);

  my $null = open '/dev/null', :w;

  {
    dbfile => $dbfile,
    migdir => $migdir,
    seeds  => $seeds,
    null   => $null,
    tasks  => DbTasks.new(:migration-path($migdir.Str), :$seeds, :out($null), :err($null)),
  };
}

sub cleanup(%env) {
  %env<null>.close;
  %env<dbfile>.IO.unlink if %env<dbfile>.IO.e;
  %env<seeds>.IO.unlink if %env<seeds>.IO.e;
  run 'rm', '-rf', %env<migdir>.Str;
}

sub tables(Str:D $dbfile --> Set) {
  my $h = DBIish.connect('SQLite', :database($dbfile));
  LEAVE { $h.dispose if $h.defined }
  $h.execute("SELECT name FROM sqlite_master WHERE type = 'table'").allrows.map(*[0]).Set;
}

sub widget-count(Str:D $dbfile --> Int) {
  my $h = DBIish.connect('SQLite', :database($dbfile));
  LEAVE { $h.dispose if $h.defined }
  $h.execute("SELECT COUNT(*) FROM widgets").row[0].Int;
}

describe 'database tasks', {
  context 'create and migrate', {
    it 'creates the database, applies every migration, and reports state', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;

      aggregate-failures {
        expect(%env<dbfile>.IO.e).to.be-truthy;
        expect(tables(%env<dbfile>){'gizmos'}).to.be-truthy;
        expect(%env<tasks>.version).to.eq('003');
        expect(%env<tasks>.status.grep({ .<status> eq 'up' }).elems).to.eq(3);
      }
    }
  }

  context 'rollback and redo', {
    it 'reverts the last migration and round-trips a redo', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;
      %env<tasks>.rollback(step => 1);

      aggregate-failures {
        expect(tables(%env<dbfile>){'gizmos'}).to.be-falsy;
        expect(%env<tasks>.version).to.eq('002');
      }

      %env<tasks>.redo(step => 1);
      expect(%env<tasks>.version).to.eq('002');
    }
  }

  context 'targeted migrations', {
    it 'runs single up/down and migrates to a target version', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.create;
      %env<tasks>.migrate;

      %env<tasks>.migrate-down('003');
      expect(tables(%env<dbfile>){'gizmos'}).to.be-falsy;

      %env<tasks>.migrate-up('003');
      expect(tables(%env<dbfile>){'gizmos'}).to.be-truthy;

      %env<tasks>.migrate-to('001');

      aggregate-failures {
        expect(tables(%env<dbfile>){'widgets'}).to.be-truthy;
        expect(tables(%env<dbfile>){'gadgets'}).to.be-falsy;
        expect(%env<tasks>.abort-if-pending).to.eq(1);
      }

      %env<tasks>.migrate-to('003');
      expect(%env<tasks>.abort-if-pending).to.eq(0);
    }
  }

  context 'seed, setup, reset and prepare', {
    it 'seeds and rebuilds the database', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      %env<tasks>.setup;

      aggregate-failures {
        expect(tables(%env<dbfile>){'gizmos'}).to.be-truthy;
        expect(widget-count(%env<dbfile>)).to.eq(1);
      }

      %env<tasks>.drop;
      expect(%env<dbfile>.IO.e).to.be-falsy;

      %env<tasks>.prepare;
      expect(widget-count(%env<dbfile>)).to.eq(1);

      %env<tasks>.prepare;
      expect(widget-count(%env<dbfile>)).to.eq(1);
    }
  }
}
