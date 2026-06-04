
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Colors;
use ORM::ActiveRecord::Support::Environment;
use ORM::ActiveRecord::Errors::X;

class Migrate is export {
  my Str $.dir = 'db/migrate';

  # EVAL installs each migration's `class` into GLOBAL; EVALing the same file
  # twice in one process redeclares it and dies. Cache the loaded class by path
  # so a second migrate pass (parallel workers, or a spec migrating an isolated
  # DB) reuses it. `.new` rebinds to the current DB.shared, so the cached class
  # still targets the right connection.
  my %loaded-migrations;

  has @.args;
  has DB $!db;
  has Str $.connection = default-connection();
  has Str $.migration-path;

  submethod BUILD(:@!args, Str :$connection = default-connection(), Str :$migration-path) {
    $!connection = $connection;
    $!db = DB.shared(name => $connection);
    # Per-connection migration directory: an explicit arg wins, then the
    # connection's `migration-path` / `migrations` config key, then the default.
    $!migration-path = $migration-path // self!config-migration-path // Migrate.dir;
  }

  method !config-migration-path {
    my %config = DB.read-config(name => $!connection);
    %config<migration-path> // %config<migrations>;
  }

  method run {
    if @!args.elems && @!args[0] eq 'reset' {
      return self.reset(args => @!args[1..*]);
    }
    self.check-migrations-table;
    self.do-migrations;
  }

  # Drop every table the adapter can see. Confirmation is interactive
  # ([Y/n]); pass `--yes` (or set AR_ASSUME_YES=1) to skip the prompt.
  # Returns the dropped tables for the caller (mainly for tests).
  method reset(:@args = [], :$in = $*IN, :$out = $*OUT --> List) {
    my $assume-yes = (@args.first({ $_ eq '--yes' || $_ eq '-y' }).defined)
                     || (%*ENV<AR_ASSUME_YES> // '') eq '1';

    my @tables = $!db.get-table-names.list;
    unless @tables.elems {
      $out.say('Nothing to drop — no tables present.');
      return ();
    }

    $out.say('About to DROP these tables:');
    $out.say('  ' ~ $_) for @tables;
    unless $assume-yes {
      $out.print('Proceed? [Y/n] ');
      $out.flush;
      my $answer = $in.get // '';
      unless self!is-yes($answer) {
        $out.say(red('Aborted. No tables were dropped.'));
        return ();
      }
    }

    my @dropped = $!db.ddl-drop-all-tables.list;
    $out.say(green('Dropped ' ~ @dropped.elems ~ ' table' ~ (@dropped.elems == 1 ?? '' !! 's') ~ '.'));
    @dropped;
  }

  # Empty input (just Enter) and a leading Y/y both confirm. Anything else
  # stops.
  method !is-yes(Str:D $answer --> Bool) {
    return True if $answer eq '';
    my $first = $answer.substr(0, 1);
    $first eq 'Y' || $first eq 'y';
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

    my @files = self.files($!migration-path).sort;
    @files .= reverse if $action ~~ 'down';

    for @files -> $path {
      next unless IO::Path.new($path).basename ~~ /^$<version>=(\d+) '-' $<name>=(.*) \.raku/;
      next unless $count == 0 || $cnt < $count;

      my $version = $<version>.Str;
      my $last = self.last;
      next unless $action ~~ 'down' && $version == $last || $action ~~ 'up' && $version > $last;

      # Migration progress goes to stdout, which behave parses as JSON events
      # under --parallel; stay quiet when SQL logging is disabled (specs/tests).
      unless %*ENV<DISABLE-SQL-LOG> {
        say '';
        say $action ~~ 'up' ?? green('↑ ' ~ $path ~ ' ↑') !! red('↓ ' ~ $path ~ ' ↓');
      }

      my $migration = self!load-migration($path);
      my $instance  = $migration.new;
      my $wrap      = self.wraps-in-transaction($instance);

      $!db.begin if $wrap;

      try {
        CATCH {
          when X::IrreversibleMigration {
            say 'Irreversible migration detected in ' ~ $path;
            Exception.new.throw;
          }
        }

        $instance."$action"();
      }

      $action ~~ 'up' ?? self.add(:$version) !! self.rm(:$version);
      $!db.commit if $wrap;

      $cnt++;
    }
  }

  # A migration runs inside a BEGIN/COMMIT unless it opts out via
  # `disable-ddl-transaction` (e.g. for CREATE INDEX CONCURRENTLY).
  method wraps-in-transaction($migration --> Bool) {
    !$migration.disable-ddl-transaction;
  }

  method !load-migration(Str:D $path) {
    return %loaded-migrations{$path} if %loaded-migrations{$path}:exists;
    %loaded-migrations{$path} = EVAL $path.IO.slurp;
  }

  method add(Str:D :$version) {
    $!db.exec(qq:to/SQL/);
      INSERT INTO migrations (version)
      VALUES ('$version')
      SQL
  }

  method rm(Str:D :$version) {
    $!db.exec(qq:to/SQL/);
      DELETE FROM migrations
      WHERE version LIKE '$version'
      SQL
  }

  method files(Str:D $dir) {
    unless $dir.IO.d {
      say "`$dir` directory not found\n";
      exit 1;
    }

    gather for dir $dir -> $path {
      take $path.Str if $path.basename ~~ /^\d+ '-' <[\w\-]>+ \.raku$/;
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
    $!db.ddl-create-table('migrations', [
      version => { :string },
    ]);
  }

  method migrations-table-exists(--> Bool) {
    so $!db.get-table-names.grep(* eq 'migrations').elems;
  }
}
