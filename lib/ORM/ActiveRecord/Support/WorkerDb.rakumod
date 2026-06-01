unit module ORM::ActiveRecord::Support::WorkerDb;

# behave exports BEHAVE_WORKER_INDEX (0..N-1) into each parallel worker
# subprocess. Returns the Int type object when unset, so callers can guard
# with `.defined`.
sub worker-index(--> Int) is export {
  my $raw = %*ENV<BEHAVE_WORKER_INDEX>;
  return Int unless $raw.defined && $raw ~~ /^ \d+ $/;
  $raw.Int;
}

# behave's concurrency cap for this run, from BEHAVE_WORKER_COUNT (1 in serial
# mode). This is how many distinct worker slots exist, hence how many per-worker
# databases are in play.
sub worker-count(--> Int) is export {
  my $raw = %*ENV<BEHAVE_WORKER_COUNT>;
  return 1 unless $raw.defined && $raw ~~ /^ \d+ $/;
  $raw.Int;
}

# True when we're a behave parallel worker (a slot index, and more than one
# worker) — the only time per-worker database suffixing applies. A serial run
# (count 1) or a non-behave process leaves it off, so ordinary runs use the base
# database. No extra env var to set: behave already provides both signals.
sub per-worker-dbs-active(--> Bool) is export {
  worker-index().defined && worker-count() > 1;
}

# Insert `_$idx` before the file extension: db/test.sqlite3 -> db/test_3.sqlite3.
# A path with no extension just gets the suffix appended.
sub suffix-sqlite-path(Str:D $path, Int:D $idx --> Str) {
  return "{$0}_{$idx}.{$1}" if $path ~~ /^ (.*) '.' (<-[./]>+) $/;
  "{$path}_$idx";
}

# Give each worker its own database so concurrent workers never share state.
# pg/mysql: <name> -> <name>_$idx. sqlite file: suffix the path. sqlite
# :memory: is per-process already, so it is a no-op. The name lives under
# `name` (config/application.json) or `database` (a parsed DATABASE_URL);
# whichever is present is suffixed in place.
sub apply-worker-suffix(%config, Int:D $idx --> Hash) is export {
  my %out = %config;

  my $key = (%out<name>:exists) ?? 'name' !! 'database';
  my $val = %out{$key};
  return %out unless $val.defined && $val ne '';

  my $adapter = (%out<adapter> // 'pg').lc;
  my $sqlite  = $adapter eq 'sqlite' || $adapter eq 'sqlite3';

  if $sqlite {
    return %out if $val eq ':memory:';
    %out{$key} = suffix-sqlite-path($val, $idx);
  } else {
    %out{$key} = "{$val}_$idx";
  }

  %out;
}
