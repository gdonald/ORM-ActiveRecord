
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;

class Migrate is export {
  my Str $.migrations-dir = 'db/migrate';

  has @.args;
  has DB $!db;

  submethod BUILD(:@!args) {
    $!db = DB.new;

    self.check-migrations-table;
    self.do-migrations;
  }

  method do-migrations {
    if not @!args.elems {
      self.migrate-up(0);
    } elsif @!args.elems == 1 {
      my $action = '';
      my $count = 0;
      if @!args[0] ~~ /(<[\w]>+) [':' (<[\d]>+)]?/ {
        $action = $0 ?? $0 !! '';
        $count = $1 ?? $1.Int !! 0;
      }

      if $action ~~ 'up' {
        self.migrate-up($count);
      } elsif $action ~~ 'down' {
        self.migrate-down($count);
      }
    }
  }

  method migrate-up($count) {
    my $cnt = 0;
    for self.migration-files(Migrate.migrations-dir).sort -> $path {
      if IO::Path.new($path).basename ~~ /^(\d+) '-' (.*) \.p6/ {
        if $0 > self.last-migration && ($count == 0 || $cnt++ < $count) {
          say $path;
          my $str = $path.IO.slurp.trim;
          EVAL $str;
          my $klass = $1.split('-').map({ $_.tc }).join;
          $!db.begin-transaction;
          EVAL "$klass.new.up";
          self.add-migration($0.Str);
          $!db.commit-transaction;
        }
      }
    }
  }

  method migrate-down($count) {
    my $cnt = 0;
    for self.migration-files(Migrate.migrations-dir).sort.reverse -> $path {
      if IO::Path.new($path).basename ~~ /^(\d+) '-' (.*) \.p6/ {
        if $0 == self.last-migration && ($count == 0 || $cnt++ < $count) {
          say $path;
          my $str = $path.IO.slurp.trim;
          EVAL $str;
          my $klass = $1.split('-').map({ $_.tc }).join;
          $!db.begin-transaction;
          EVAL "$klass.new.down";
          self.rm-migration($0);
          $!db.commit-transaction;
        }
      }
    }
  }

  method add-migration($version) {
    $!db.execute(qq:to/SQL/);
      INSERT INTO migrations (version)
      VALUES ('$version')
    SQL
  }

  method rm-migration($version) {
    my $sql = qq:to/SQL/;
      DELETE FROM migrations
      WHERE version LIKE '$version'
    SQL

    $!db.execute($sql);
  }

  method migration-files($dir) {
    unless $dir.IO.d {
      say "`$dir` directory not found\n";
      exit 1;
    }

    gather for dir $dir -> $path {
      if $path.basename ~~ /^\d+ '-' <[\w\-]>+ \.p6$/ { take $path.Str }
    }
  }

  method last-migration {
    my $sql = qq:to/SQL/;
      SELECT version
      FROM migrations
      ORDER BY id DESC
      LIMIT 1
    SQL

    my @res = $!db.execute($sql);
    @res.elems ?? @res[0][0] !! '';
  }

  method check-migrations-table {
    return if self.migrations-table-exists;
    self.create-migrations-table;
  }

  method create-migrations-table {
    my $sql = qq:to/SQL/;
      CREATE TABLE migrations (
        id serial,
        version character varying
      );
    SQL

    $!db.execute($sql);
  }

  method migrations-table-exists {
    my $sql = qq:to/SQL/;
      SELECT EXISTS (
        SELECT 1
        FROM pg_tables
        WHERE schemaname = '{$!db.schema}'
        AND tablename = 'migrations'
      )
    SQL

    my @res = $!db.execute($sql);
    @res[0][0];
  }
}
