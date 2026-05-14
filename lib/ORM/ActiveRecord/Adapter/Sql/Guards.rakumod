
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

  method check-write-allowed(Str:D $sql) {
    return unless $!write-prohibition-depth > 0;
    return unless self.is-write-sql($sql);
    die X::ReadOnlyDatabase.new(:$sql);
  }

  method is-write-sql(Str:D $sql --> Bool) {
    my $stripped = $sql;
    $stripped ~~ s:g/ '/*' .*? '*/' //;
    $stripped ~~ s/ ^ \s+ //;
    return True if $stripped ~~ /^ :i (insert | update | delete | replace | truncate | merge) <|w> /;
    return True if $stripped ~~ /^ :i 'with' <|w> .*? <|w> (insert | update | delete | replace | merge) <|w> /;
    False;
  }
}
