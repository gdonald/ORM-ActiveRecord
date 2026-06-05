
use Log::Async;
use ORM::ActiveRecord::Support::Colors;

logger.send-to($*OUT, :level(INFO));

with %*ENV<ORM_LOG_FILE> -> $path {
  logger.send-to($path, :level(ERROR)) if $path.chars;
}

class Log is export {
  method sql(Str:D :$sql) {
    return if %*ENV<DISABLE-SQL-LOG>;

    my $log = $sql.trans(/\n/ => ' ', /<[\s]>+/ => ' ');
    given $log {
      when $_ ~~ /:i (BEGIN|COMMIT)/ { info yellow($_) }
      when $_ ~~ /:i (INSERT|CREATE|ALTER)/ { info green($_) }
      when $_ ~~ /:i (DROP|DELETE)/ { info red($_) }
      default { info blue($_) }
    }
  }

  method query(Str:D :$sql, :$ms, Bool :$slow = False) {
    return if %*ENV<DISABLE-SQL-LOG>;

    my $line = ($slow ?? 'SLOW ' !! '') ~ "({$ms}ms) " ~ $sql.trans(/\n/ => ' ', /<[\s]>+/ => ' ');
    $slow ?? warning(red($line)) !! info(blue($line));
  }
}
