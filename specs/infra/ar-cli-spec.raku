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

  it 'documents the generate subcommand', {
    expect(ar-output('--help').contains('generate')).to.be-truthy;
  }

  it 'documents the destroy subcommand', {
    expect(ar-output('--help').contains('destroy')).to.be-truthy;
  }

  it 'documents the db: tasks', {
    expect(ar-output('--help').contains('db:migrate')).to.be-truthy;
  }

  it 'documents the schema tasks', {
    expect(ar-output('--help').contains('db:schema:dump')).to.be-truthy;
  }

  it 'documents the runtime tasks', {
    expect(ar-output('--help').contains('runner')).to.be-truthy;
  }
}

describe 'ar runtime tasks', {
  it 'runs inline code', {
    expect(ar-output('runner', 'say 13 + 29').contains('42')).to.be-truthy;
  }

  it 'reports stats', {
    expect(ar-output('stats').contains('Migrations:')).to.be-truthy;
  }
}

describe 'ar generate migration', {
  it 'writes a migration file under db/migrate', {
    my $repo = $*CWD;
    my $tmp  = $*TMPDIR.add('ar-cli-generate-' ~ $*PID);
    $tmp.mkdir;

    LEAVE { run 'rm', '-rf', $tmp.Str }

    my $proc = run 'raku', '-I', $repo.add('lib').Str, $repo.add('bin/ar').Str,
      'generate', 'migration', 'CreateThings', 'name:string',
      :cwd($tmp.Str), :out, :err;
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);

    my @migrations = $tmp.add('db/migrate').d
      ?? $tmp.add('db/migrate').dir.grep(*.basename.ends-with('-create-things.raku')).list
      !! ();

    expect(@migrations.elems).to.eq(1);
  }
}
