
unit module ORM::ActiveRecord::Support::TestSkip;

use Test;
use JSON::Tiny;
use ORM::ActiveRecord::Support::DatabaseUrl;

sub normalize-adapter-name(Str:D $name --> Str) is export {
  given $name.lc {
    when 'pg' | 'postgres' | 'postgresql' { 'pg' }
    when 'mysql' | 'mysql2' | 'mariadb'   { 'mysql' }
    when 'sqlite' | 'sqlite3'             { 'sqlite' }
    default { $name.lc }
  }
}

# The canonical name of a live adapter object (DB.shared.adapter), regardless of
# how the connection was configured (DATABASE_URL or config/application.json).
# This is the authoritative answer to "what am I actually connected to", which
# DATABASE_URL alone cannot give for a config-driven run.
sub live-adapter-name($adapter --> Str) is export {
  return Str unless $adapter.defined;
  given $adapter.^name {
    when /'Sqlite'/ { 'sqlite' }
    when /'Pg'/     { 'pg' }
    when /'MySql'/  { 'mysql' }
    default         { Str }
  }
}

sub configured-adapter-name(Str :$config-path, Bool :$check-config = $config-path.defined --> Str) is export {
  if my $url = %*ENV<DATABASE_URL> {
    my %c = parse-database-url($url);
    return normalize-adapter-name(%c<adapter>) if %c<adapter>;
  }
  if $check-config {
    my $path = $config-path // 'config/application.json';
    if $path.IO.e {
      my $json = try { from-json($path.IO.slurp) };
      if $json && $json<db> && $json<db><adapter> {
        return normalize-adapter-name($json<db><adapter>);
      }
    }
  }
  Str;
}

sub coerce-adapter-list($adapter --> List) {
  my @raw = $adapter ~~ Positional ?? $adapter.List !! ($adapter,);
  @raw.map(-> $a { normalize-adapter-name($a.Str) }).list;
}

sub adapter-matches(:$adapter! --> Bool) is export {
  my $current = configured-adapter-name();
  return False without $current;
  my @list = coerce-adapter-list($adapter);
  ($current eq any(@list)).so;
}

sub skip-on(:$adapter!, Str :$reason) is export {
  return False unless adapter-matches(:$adapter);
  my $current = configured-adapter-name();
  plan 1;
  skip $reason // "skipped on adapter '$current'";
  exit 0;
}

sub only-on(:$adapter!, Str :$reason) is export {
  my $current = configured-adapter-name();
  return False without $current;
  return False if adapter-matches(:$adapter);
  my @list = coerce-adapter-list($adapter);
  plan 1;
  skip $reason // "only runs on adapter(s) " ~ @list.join(', ') ~ ", current is '$current'";
  exit 0;
}
