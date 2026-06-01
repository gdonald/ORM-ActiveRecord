unit module ORM::ActiveRecord::Support::Environment;

# Active environment name. AR_ENV wins; otherwise anything running under behave
# (BEHAVE_WORKER_COUNT is always set there) is a test run, so default to 'test'.
# Failing both, the caller's default (bin/ar -> development).
sub current-env(Str:D $default = 'development' --> Str) is export {
  my $env = %*ENV<AR_ENV>;
  return $env if $env.defined && $env ne '';
  return 'test' if %*ENV<BEHAVE_WORKER_COUNT>.defined;
  $default;
}

# The connection a model (or DB.shared) uses unless told otherwise.
sub default-connection(--> Str) is export {
  'primary';
}
