
use Log::Async;
logger.send-to($*OUT, :level(INFO));
logger.send-to('log/error.log', :level(ERROR));

use ORM::ActiveRecord::Colors;

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
}
