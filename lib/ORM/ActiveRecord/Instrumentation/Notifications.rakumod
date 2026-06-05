
# A small ActiveSupport::Notifications-style pub/sub. Subscribers register a
# callback for a named event and receive the event's payload (a Hash). The
# state is process-wide, held in class-level lexicals.
class Notifications is export {
  my %subscribers;     # event name => Array of %( id => Int, callback => &cb )
  my Int $next-id = 0;

  method subscribe(Str:D $event, &callback --> Int) {
    my $id = $next-id++;
    %subscribers{$event} //= [];
    %subscribers{$event}.push: %( :$id, :&callback );
    $id;
  }

  method unsubscribe(Int:D $id --> Bool) {
    my $removed = False;

    for %subscribers.keys -> $event {
      my $before = %subscribers{$event}.elems;
      %subscribers{$event} = %subscribers{$event}.grep({ $_<id> != $id }).Array;
      $removed = True if %subscribers{$event}.elems != $before;
    }

    $removed;
  }

  method has-subscribers(Str:D $event --> Bool) {
    so %subscribers{$event} && %subscribers{$event}.elems;
  }

  # Fire an instantaneous event (no timing).
  method notify(Str:D $event, %payload) {
    return unless self.has-subscribers($event);
    .<callback>(%payload) for %subscribers{$event}.list;
  }

  # Run a block, time it, and notify subscribers with the duration (seconds)
  # merged into the payload. When the block throws, subscribers still see the
  # event (with the exception in the payload) and the error is rethrown.
  method instrument(Str:D $event, %payload is copy, &block) {
    return block() unless self.has-subscribers($event);

    my $start = now;
    my $result;
    my $error;

    {
      CATCH { default { $error = $_ } }
      $result = block();
    }

    %payload<duration>  = (now - $start).Num;
    %payload<exception> = $error if $error;
    self.notify($event, %payload);

    $error.rethrow if $error;
    $result;
  }

  method reset { %subscribers = (); $next-id = 0; }
}
