
unit module ORM::ActiveRecord::Connection::Switching;

# Dynamic connection context for `connected-to`. Process-wide defaults mean the
# dynamic variables always resolve (to an undefined Str) without a connected-to
# block in scope, so reading them never throws.
PROCESS::<$AR-ROLE>       = Str;
PROCESS::<$AR-SHARD>      = Str;
PROCESS::<$AR-CONNECTION> = Str;

sub active-role       is export { $*AR-ROLE }
sub active-shard      is export { $*AR-SHARD }
sub active-connection is export { $*AR-CONNECTION }

# Rails-style automatic role selector. A web middleware asks `role-for` which
# role a request should use: writes (and reads for a short window after a
# write, so a user sees their own change) go to `writing`; everything else to
# `reading`. Call `record-write` after a write.
#
#   my $sel = DatabaseSelector.new(delay => 2);
#   Model.connected-to(role => $sel.role-for(:write($is-mutating)), { ... });
#   $sel.record-write if $is-mutating;
class DatabaseSelector is export {
  has Real    $.delay = 2.0;
  has Instant $!last-write;

  method record-write {
    $!last-write = now;
  }

  method role-for(Bool :$write = False --> Str) {
    return 'writing' if $write;
    return 'writing' if $!last-write.defined && (now - $!last-write) < $!delay;
    'reading';
  }
}
