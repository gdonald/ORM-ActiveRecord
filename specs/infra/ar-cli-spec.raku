use lib 'lib';
use BDD::Behave;

%*ENV<DISABLE-SQL-LOG> = True;

sub ar-output(*@args --> Str) {
  my $proc = run 'raku', '-Ilib', 'bin/ar', |@args, :out, :err;
  my $out = $proc.out.slurp(:close);
  $proc.err.slurp(:close);
  $out;
}

describe 'ar --version', {
  it 'prints the distribution name', {
    expect(ar-output('--version').contains('ORM::ActiveRecord')).to.be-truthy;
  }

  it 'prints a version number', {
    expect(ar-output('--version') ~~ /\d+ '.' \d+/).to.be-truthy;
  }
}

describe 'ar --help', {
  it 'shows usage', {
    expect(ar-output('--help').contains('Usage:')).to.be-truthy;
  }

  it 'documents the createdb subcommand', {
    expect(ar-output('--help').contains('createdb')).to.be-truthy;
  }

  it 'documents the migrate subcommand', {
    expect(ar-output('--help').contains('migrate')).to.be-truthy;
  }
}
