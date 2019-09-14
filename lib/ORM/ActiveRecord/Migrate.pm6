
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Colors;

class Migrate is export {
  my Str $.dir = 'db/migrate';

  has @.args;
  has DB $!db;

  submethod BUILD(:@!args) {
    $!db = DB.new;

    self.check-migrations-table;
    self.do-migrations;
  }

  method do-migrations {
    if not @!args.elems {
      self.migrate(['up', 0]);
    } elsif @!args.elems == 1 {
      self.migrate(self.action-count);
    }
  }

  method action-count {
    my ($action, $count) = '', 0;

    if @!args[0] ~~ /(up|down) [':' (<[\d]>+)]?/ {
      $action = $0 ?? $0 !! '';
      $count = $1 ?? $1.Int !! 0;
    }

    $action, $count;
  }

  method migrate(|ac) {
    my ($action, $count) = ac[0];
    my $cnt = 0;

    my @files = self.files(Migrate.dir).sort;
    @files .= reverse if $action ~~ 'down';

    for @files -> $path {
      next unless IO::Path.new($path).basename ~~ /^$<version>=(\d+) '-' $<name>=(.*) \.p6/;
      next unless $count == 0 || $cnt < $count;

      my $v = $<version>.Str;
      my $last = self.last;
      next unless $action ~~ 'down' && $v == $last || $action ~~ 'up' && $v > $last;

      say '';
      say $action ~~ 'up' ?? green('↑ ' ~ $path ~ ' ↑') !! red('↓ ' ~ $path ~ ' ↓');
      EVAL $path.IO.slurp;

      $!db.begin;
      EVAL "{$<name>.Str.split('-').map({ $_.tc }).join}.new.$action";
      $action ~~ 'up' ?? self.add($v) !! self.rm($v);
      $!db.commit;

      $cnt++;
    }
  }

  method add($version) {
    $!db.exec(qq:to/SQL/);
      INSERT INTO migrations (version)
      VALUES ('$version')
      SQL
  }

  method rm($version) {
    $!db.exec(qq:to/SQL/);
      DELETE FROM migrations
      WHERE version LIKE '$version'
      SQL
  }

  method files($dir) {
    unless $dir.IO.d {
      say "`$dir` directory not found\n";
      exit 1;
    }

    gather for dir $dir -> $path {
      if $path.basename ~~ /^\d+ '-' <[\w\-]>+ \.p6$/ { take $path.Str }
    }
  }

  method last {
    my $sql = qq:to/SQL/;
      SELECT version
      FROM migrations
      ORDER BY id DESC
      LIMIT 1
      SQL

    my @res = $!db.exec($sql);
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
      )
      SQL

    $!db.exec($sql);
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

    my @res = $!db.exec($sql);
    @res[0][0];
  }
}
