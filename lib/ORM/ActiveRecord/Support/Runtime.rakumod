
use MONKEY-SEE-NO-EVAL;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Environment;

# Backing logic for the `ar` runtime subcommands (console, runner, dbconsole,
# notes, stats). The methods return data or command vectors rather than
# launching processes, so the CLI does the exec/print and the behaviour stays
# testable.
class Runtime is export {
  has Str $.path = 'config/application.json';
  has Str $.env  = current-env('development');

  my @SOURCE-EXTENSIONS = <raku rakumod rakutest>;
  my @DEFAULT-TAGS      = <TODO FIXME OPTIMIZE HACK XXX>;

  # --- runner -------------------------------------------------------------

  method run-code(Str:D $code) {
    EVAL $code;
  }

  method run-script(Str:D $path) {
    die "runner: file not found: $path" unless $path.IO.e;
    EVAL $path.IO.slurp;
  }

  # --- console ------------------------------------------------------------

  method default-includes {
    <lib app/models app/validators>.grep(*.IO.d).list;
  }

  method console-command(:@includes = self.default-includes --> List) {
    ('raku', |@includes.map({ '-I' ~ $_ })).List;
  }

  # --- dbconsole ----------------------------------------------------------

  method dbconsole-command(--> Hash) {
    self.client-command(DB.read-config(:$!path, :$!env));
  }

  method client-command(%cfg --> Hash) {
    given (%cfg<adapter> // 'pg').lc {
      when 'sqlite' | 'sqlite3' {
        %( argv => ['sqlite3', %cfg<name> // %cfg<database> // ':memory:'], env => {} );
      }
      when 'pg' | 'postgres' | 'postgresql' {
        %(
          argv => [
            'psql',
            '-h', (%cfg<host> // 'localhost'),
            '-p', (%cfg<port> // 5432).Str,
            '-U', (%cfg<user> // ''),
            (%cfg<name> // %cfg<database>),
          ],
          env => %( PGPASSWORD => %cfg<password> // '' ),
        );
      }
      when 'mysql' | 'mysql2' | 'mariadb' {
        %(
          argv => [
            'mysql',
            '-h', (%cfg<host> // '127.0.0.1'),
            '-P', (%cfg<port> // 3306).Str,
            '-u', (%cfg<user> // 'root'),
            ('--password=' ~ (%cfg<password> // '')),
            (%cfg<name> // %cfg<database>),
          ],
          env => {},
        );
      }
      default { die "dbconsole: unsupported adapter '{%cfg<adapter> // ''}'" }
    }
  }

  # --- notes --------------------------------------------------------------

  method scan-notes(@roots, :@tags = @DEFAULT-TAGS --> List) {
    my @notes;
    for @roots.grep(*.IO.e) -> $root {
      for self!source-files($root) -> $file {
        my $number = 0;
        for $file.IO.lines -> $line {
          $number++;
          with self!note-for($line, @tags) -> %note {
            @notes.push: %( file => $file.Str, line => $number, |%note );
          }
        }
      }
    }
    @notes.List;
  }

  method !note-for(Str:D $line, @tags --> Hash) {
    for @tags -> $tag {
      if $line ~~ / '#' \s* $tag [ ':' | \s ]? \s* $<text>=(.*) $ / {
        return %( tag => $tag, text => ~$<text> );
      }
    }
    Hash;
  }

  method !source-files($root --> List) {
    my $io = $root.IO;
    return ($io,).List if $io.f;
    return ().List unless $io.d;

    my @out;
    for $io.dir -> $entry {
      next if $entry.basename.starts-with('.');
      if $entry.d {
        @out.append: self!source-files($entry);
      } elsif @SOURCE-EXTENSIONS.first({ $entry.extension eq $_ }) {
        @out.push: $entry;
      }
    }
    @out.sort(*.Str).List;
  }

  # --- stats --------------------------------------------------------------

  method compute-stats(:@code-dirs = <lib app/models app/validators>,
                       Str :$migrate-dir = 'db/migrate' --> Hash) {
    my $files = 0;
    my $lines = 0;
    my $code  = 0;
    my $models = 0;

    for @code-dirs.grep(*.IO.d) -> $dir {
      for self!source-files($dir) -> $file {
        $files++;
        for $file.IO.lines -> $line {
          $lines++;
          my $trimmed = $line.trim;
          next if $trimmed eq '';
          next if $trimmed.starts-with('#');
          $code++;
          $models++ if $line ~~ / 'is' \s+ 'Model' >> /;
        }
      }
    }

    my $migrations = $migrate-dir.IO.d
      ?? $migrate-dir.IO.dir.grep({ .basename ~~ /^ \d+ '-' <[\w\-]>+ '.raku' $ / }).elems
      !! 0;

    %( :$files, :$lines, :$code, :$models, :$migrations );
  }
}
