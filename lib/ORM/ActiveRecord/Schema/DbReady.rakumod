use DBIish;

unit module ORM::ActiveRecord::Schema::DbReady;

# Read-only readiness checks for a single configured database. Used by the
# launcher's pre-flight (test.raku / `ar check`) to confirm every expected
# database exists and is fully migrated before any specs run. These never
# create or alter anything. Kept free of any DB/adapter dependency to avoid a
# cycle.

sub db-name(%cfg --> Str) { %cfg<name> // %cfg<database> // '' }

sub file-versions(Str $dir) {
  (gather for $dir.IO.dir -> $p {
    take ~$0 if $p.basename ~~ /^ (\d+) '-' /;
  }).unique;
}

# Connect to the configured database itself (not an admin database). Returns a
# DBIish handle, or Nil when the database does not exist / cannot be reached.
# Note: sqlite is excluded here — connecting would create the file, defeating
# the existence check; callers test the file path directly.
sub connect-db(%cfg) {
  given (%cfg<adapter> // 'pg').lc {
    when 'pg' | 'postgres' | 'postgresql' {
      try DBIish.connect('Pg',
        host     => %cfg<host>     // 'localhost',
        port     => (%cfg<port>    // 5432).Int,
        user     => %cfg<user>     // '',
        password => %cfg<password> // '',
        database => db-name(%cfg),
      );
    }
    when 'mysql' | 'mysql2' | 'mariadb' {
      try DBIish.connect('mysql',
        host     => %cfg<host>     // '127.0.0.1',
        port     => (%cfg<port>    // 3306).Int,
        user     => %cfg<user>     // 'root',
        password => %cfg<password> // '',
        database => db-name(%cfg),
      );
    }
    default { Nil }
  }
}

# True when db/migrate/ holds migration versions not recorded in the database's
# `migrations` table (an absent table counts as everything pending).
sub pending-on-handle($h, Str :$dir --> Bool) {
  return False unless $dir.IO.d;

  my @file-versions = file-versions($dir);
  return False unless @file-versions;

  my %applied;
  my $read = try {
    for $h.execute('SELECT version FROM migrations').allrows -> $row {
      %applied{ ~$row[0] } = True;
    }
    True;
  };
  return True unless $read;

  so @file-versions.first({ !%applied{$_} });
}

# Readiness of one configured database: 'missing' (does not exist), 'pending'
# (exists but has unrun migrations), or 'ready'. sqlite :memory: is ephemeral
# and always reported ready.
sub database-status(%cfg, Str :$dir = 'db/migrate' --> Str) is export {
  given (%cfg<adapter> // 'pg').lc {
    when 'sqlite' | 'sqlite3' {
      my $path = db-name(%cfg) || ':memory:';
      return 'ready' if $path eq ':memory:';
      return 'missing' unless $path.IO.e;

      my $h = try { DBIish.connect('SQLite', database => $path) };
      return 'missing' unless $h.defined;
      LEAVE { $h.dispose if $h.defined }
      return pending-on-handle($h, :$dir) ?? 'pending' !! 'ready';
    }
    default {
      my $h = connect-db(%cfg);
      return 'missing' unless $h.defined;
      LEAVE { $h.dispose if $h.defined }
      return pending-on-handle($h, :$dir) ?? 'pending' !! 'ready';
    }
  }
}
