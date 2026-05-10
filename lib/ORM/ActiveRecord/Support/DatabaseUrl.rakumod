
unit module ORM::ActiveRecord::Support::DatabaseUrl;

sub url-decode(Str:D $s --> Str) {
  $s.subst(/'%' (<xdigit><xdigit>)/, { :16(~$0).chr }, :g);
}

sub parse-database-url(Str:D $url --> Hash) is export {
  my $colon = $url.index(':');
  die "DATABASE_URL: missing scheme separator in '$url'" without $colon;

  my $scheme = $url.substr(0, $colon).lc;
  my $rest   = $url.substr($colon + 1);

  my %out;
  given $scheme {
    when 'pg' | 'postgres' | 'postgresql' { %out<adapter> = 'pg' }
    when 'mysql' | 'mysql2' | 'mariadb'   { %out<adapter> = 'mysql' }
    when 'sqlite' | 'sqlite3'             { %out<adapter> = 'sqlite' }
    default { die "DATABASE_URL: unsupported scheme '$scheme'" }
  }

  if %out<adapter> eq 'sqlite' {
    my $path = $rest;
    if $path.starts-with('///') {
      $path = $path.substr(2);
    } elsif $path.starts-with('//') {
      $path = $path.substr(2);
    }
    %out<database> = url-decode($path);
    return %out;
  }

  my $body = $rest;
  $body = $body.substr(2) if $body.starts-with('//');

  my $query = '';
  with $body.index('?') -> $q {
    $query = $body.substr($q + 1);
    $body  = $body.substr(0, $q);
  }

  my $path = '';
  with $body.index('/') -> $sl {
    $path = $body.substr($sl + 1);
    $body = $body.substr(0, $sl);
  }

  my ($userinfo, $hostpart) = '', $body;
  with $body.rindex('@') -> $at {
    $userinfo = $body.substr(0, $at);
    $hostpart = $body.substr($at + 1);
  }

  if $userinfo {
    with $userinfo.index(':') -> $c {
      %out<user>     = url-decode($userinfo.substr(0, $c));
      %out<password> = url-decode($userinfo.substr($c + 1));
    } else {
      %out<user> = url-decode($userinfo);
    }
  }

  if $hostpart {
    with $hostpart.index(':') -> $c {
      my $h = $hostpart.substr(0, $c);
      my $p = $hostpart.substr($c + 1);
      %out<host> = $h    if $h;
      %out<port> = $p.Int if $p;
    } else {
      %out<host> = $hostpart;
    }
  }

  %out<name> = url-decode($path) if $path;

  if $query {
    for $query.split('&') -> $pair {
      next unless $pair;
      with $pair.index('=') -> $eq {
        %out{ url-decode($pair.substr(0, $eq)) } = url-decode($pair.substr($eq + 1));
      } else {
        %out{ url-decode($pair) } = '';
      }
    }
  }

  %out;
}
