
use Log::Async;
use JSON::Tiny;
use ORM::ActiveRecord::Support::Colors;

logger.send-to($*OUT, :level(INFO));

with %*ENV<ORM_LOG_FILE> -> $path {
  logger.send-to($path, :level(ERROR)) if $path.chars;
}

# SQL / query logging with a small structured-config layer: a minimum level, a
# text-or-JSON formatter, ANSI colour toggle, and a pluggable sink. The
# defaults reproduce the original colourised text routed through Log::Async.
class Log is export {
  my Str  $level  = 'info';     # debug | info | warn | error
  my Str  $format = 'text';     # text | json
  my Bool $colour = True;
  my      &log-sink;            # Callable($line, $level) or undefined

  my %LEVEL-RANK = debug => 0, info => 1, warn => 2, error => 3;

  method configure(:$level, :$format, :$formatter, :$colour, :&sink) {
    self.set-level($_)  with $level;
    self.set-format($_) with ($format // $formatter);
    $colour = ?$_       with $colour;
    &log-sink = &sink   if &sink;
  }

  method set-level(Str:D $value)   { $level  = $value.lc }
  method set-format(Str:D $value)  { $format = $value.lc }
  method set-colour(Bool:D $value) { $colour = $value }
  method set-sink(&block)          { &log-sink = &block }

  method reset {
    $level    = 'info';
    $format   = 'text';
    $colour   = True;
    &log-sink = Callable;
  }

  method sql(Str:D :$sql) {
    self!emit(%( kind => 'sql', level => 'info', :$sql ));
  }

  method query(Str:D :$sql, :$ms, Bool :$slow = False, :@binds) {
    self!emit(%( kind => 'query', level => ($slow ?? 'warn' !! 'info'), :$sql, :$ms, :$slow, :@binds ));
  }

  method !emit(%entry) {
    return if %*ENV<DISABLE-SQL-LOG>;
    return unless %LEVEL-RANK{%entry<level>} >= %LEVEL-RANK{$level};

    my $line = $format eq 'json' ?? self!format-json(%entry) !! self!format-text(%entry);

    if &log-sink.defined {
      log-sink($line, %entry<level>);
    } else {
      %entry<level> eq 'warn' | 'error' ?? warning($line) !! info($line);
    }
  }

  method !collapse(Str:D $sql --> Str) {
    $sql.trans(/\n/ => ' ', /<[\s]>+/ => ' ');
  }

  method !render-bind($value --> Str) {
    return 'NULL'     without $value;
    return $value.Str if $value ~~ Numeric | Bool;
    "'" ~ $value.Str ~ "'";
  }

  method !binds-suffix(@binds --> Str) {
    return '' unless @binds.elems;
    ' [binds: ' ~ @binds.map({ self!render-bind($_) }).join(', ') ~ ']';
  }

  method !colour-by-type(Str:D $sql --> Str) {
    given $sql {
      when /:i (BEGIN | COMMIT) /          { yellow($sql) }
      when /:i (INSERT | CREATE | ALTER) / { green($sql) }
      when /:i (DROP | DELETE) /           { red($sql) }
      default                              { blue($sql) }
    }
  }

  method !format-text(%entry --> Str) {
    my $sql = self!collapse(%entry<sql>);

    given %entry<kind> {
      when 'sql' {
        $colour ?? self!colour-by-type($sql) !! $sql;
      }
      default {
        my $line = (%entry<slow> ?? 'SLOW ' !! '') ~ "({%entry<ms>}ms) " ~ $sql;
        $line ~= self!binds-suffix(%entry<binds>);
        $colour ?? (%entry<slow> ?? red($line) !! blue($line)) !! $line;
      }
    }
  }

  method !format-json(%entry --> Str) {
    my %out = kind => %entry<kind>, level => %entry<level>, sql => self!collapse(%entry<sql>);

    if %entry<kind> eq 'query' {
      %out<ms>    = %entry<ms>;
      %out<slow>  = %entry<slow>;
      %out<binds> = %entry<binds>.map({ .defined ?? .Str !! 'NULL' }).list if %entry<binds>.elems;
    }

    to-json(%out);
  }
}
