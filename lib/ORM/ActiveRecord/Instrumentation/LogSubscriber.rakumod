
use ORM::ActiveRecord::Instrumentation::Notifications;
use ORM::ActiveRecord::Support::Log;

# Subscribes to sql.active_record and logs each query with its timing. By
# default it logs only slow queries (those at or over the slow threshold); pass
# :log-all to log every query. A :sink callable can replace the default Log
# output, which makes the slow / log-all decision observable in tests.
class LogSubscriber is export {
  my Int $subscription-id;
  my     $threshold;             # seconds; undefined => slow detection off
  my Bool $log-all-queries = False;
  my      $log-sink;             # Callable(%payload, Bool :$slow) or undefined

  method attach(Real :$slow-threshold, Bool :$log-all = False, :$sink --> Int) {
    self.detach;

    $threshold       = $slow-threshold;
    $log-all-queries = $log-all;
    $log-sink        = $sink;

    $subscription-id = Notifications.subscribe('sql.active_record', -> %payload {
      self!handle(%payload);
    });
  }

  method detach {
    Notifications.unsubscribe($_) with $subscription-id;
    $subscription-id = Int;
  }

  method is-slow($duration-seconds --> Bool) {
    $threshold.defined && ($duration-seconds // 0) >= $threshold;
  }

  method !handle(%payload) {
    my $slow = self.is-slow(%payload<duration>);
    return unless $slow || $log-all-queries;

    $log-sink.defined
      ?? $log-sink(%payload, :$slow)
      !! self!log(%payload, :$slow);
  }

  method !log(%payload, Bool :$slow) {
    my $ms = ((%payload<duration> // 0) * 1000).round(0.1);
    Log.query(sql => %payload<sql> // '', :$ms, :$slow);
  }

  method reset {
    self.detach;
    $threshold       = Any;
    $log-all-queries = False;
    $log-sink        = Any;
  }
}
