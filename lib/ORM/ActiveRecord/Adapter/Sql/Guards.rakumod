
use ORM::ActiveRecord::Errors::X;

role SqlGuards is export {
  has Int $.write-prohibition-depth   = 0;
  has Int $.shard-swap-prohibition    = 0;
  has Int $.replica-swap-prohibition  = 0;

  method while-preventing-writes(&block) {
    $!write-prohibition-depth++;
    LEAVE $!write-prohibition-depth--;
    block();
  }

  method is-preventing-writes(--> Bool) {
    $!write-prohibition-depth > 0;
  }

  method prohibit-shard-swapping(&block) {
    $!shard-swap-prohibition++;
    LEAVE $!shard-swap-prohibition--;
    block();
  }

  method is-shard-swapping-prohibited(--> Bool) {
    $!shard-swap-prohibition > 0;
  }

  method prohibit-replica-swapping(&block) {
    $!replica-swap-prohibition++;
    LEAVE $!replica-swap-prohibition--;
    block();
  }

  method is-replica-swapping-prohibited(--> Bool) {
    $!replica-swap-prohibition > 0;
  }

  method check-write-allowed(Str:D $sql, Bool :$is-write) {
    return unless $!write-prohibition-depth > 0;
    return unless $is-write // self.is-write-sql($sql);
    die X::ReadOnlyDatabase.new(:$sql);
  }

  # Every classifier below works from the same stripped text. A caller running a
  # statement strips once and passes the result, rather than each classifier
  # redoing the two substitutions on the way to its own match.
  method strip-sql-prefix(Str:D $sql --> Str) {
    my $stripped = $sql;
    $stripped ~~ s:g/ '/*' .*? '*/' //;
    $stripped ~~ s/ ^ \s+ //;
    $stripped;
  }

  method is-write-sql(Str:D $sql --> Bool) {
    self.is-write-stripped(self.strip-sql-prefix($sql));
  }

  method is-write-stripped(Str:D $stripped --> Bool) {
    return True if $stripped ~~ /^ :i (insert | update | delete | replace | truncate | merge) <|w> /;
    return True if $stripped ~~ /^ :i 'with' <|w> .*? <|w> (insert | update | delete | replace | merge) <|w> /;
    False;
  }

  # A statement that alters the schema, so the memoized column metadata must be
  # dropped afterward.
  method is-schema-change-sql(Str:D $sql --> Bool) {
    self.is-schema-change-stripped(self.strip-sql-prefix($sql));
  }

  method is-schema-change-stripped(Str:D $stripped --> Bool) {
    so $stripped ~~ /^ :i (create | alter | drop | rename) <|w> /;
  }
}
