#!/usr/bin/env raku

use v6.d;
BEGIN { chdir $*PROGRAM.parent }

my @examples = dir('config').grep({ .basename ~~ /'application.json-' .* '-example' $/ }).sort;

my $config = 'config/application.json'.IO;
my $backup = 'config/application.json.test-all-backup'.IO;

$config.copy($backup) if $config.e;

LEAVE {
  if $backup.e {
    $backup.copy($config);
    $backup.unlink;
  }
}

my $failures = 0;

for @examples -> $example {
  say '';
  say '=' x 72;
  say "Running test.raku with {$example.basename}";
  say '=' x 72;

  $example.copy($config);

  my $proc = run './test.raku', @*ARGS;
  $failures++ unless $proc.exitcode == 0;
}

exit $failures ?? 1 !! 0;
