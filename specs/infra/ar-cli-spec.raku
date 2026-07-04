use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::WorkerDb;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $handle = DBIish.connect('SQLite', :database(':memory:'));
  $handle.dispose;
  True;
} // False;

sub ar-output(*@args --> Str) {
  my $proc = run 'raku', '-Ilib', 'bin/active-record', |@args, :out, :err;
  my $out = $proc.out.slurp(:close);
  $proc.err.slurp(:close);
  $out;
}

sub ar-exit(%env, *@args --> Int) {
  my $proc = run :env(%env), 'raku', '-Ilib', 'bin/active-record', |@args, :out, :err;
  $proc.out.slurp(:close);
  $proc.err.slurp(:close);
  $proc.exitcode;
}

sub with-temp-db(&body) {
  my $base    = $*TMPDIR.add("ar-cli-db-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
  my @workers = (^2).map: { apply-worker-suffix({ adapter => 'sqlite', name => $base }, $_)<name> };

  # Drive the CLI as a user would, outside any behave worker slot: strip the
  # worker overlay so db: tasks resolve the base (or explicitly suffixed)
  # databases rather than the runner's inherited slot.
  my %env = %*ENV.clone;
  %env<DATABASE_URL>    = "sqlite:$base";
  %env<AR_ENV>          = 'test';
  %env<DISABLE-SQL-LOG> = 'True';
  %env<BEHAVE_WORKER_INDEX>:delete;
  %env<BEHAVE_WORKER_COUNT>:delete;

  LEAVE { .IO.unlink for ($base, |@workers).grep(*.IO.e) }

  body(%env);
}

describe 'active-record version', {
  it 'prints the distribution name', {
    expect(ar-output('version').contains('ORM::ActiveRecord')).to.be-truthy;
  }

  it 'prints a version number', {
    expect(ar-output('version') ~~ /\d+ '.' \d+/).to.be-truthy;
  }

  it 'accepts --version as an alias', {
    expect(ar-output('--version').contains('ORM::ActiveRecord')).to.be-truthy;
  }
}

describe 'active-record help', {
  it 'shows usage', {
    expect(ar-output('help').contains('Usage:')).to.be-truthy;
  }

  it 'accepts --help as an alias', {
    expect(ar-output('--help').contains('Usage:')).to.be-truthy;
  }

  it 'documents the db:create task', {
    expect(ar-output('help').contains('db:create')).to.be-truthy;
  }

  it 'documents the db:migrate task', {
    expect(ar-output('help').contains('db:migrate')).to.be-truthy;
  }

  it 'documents the db:check task', {
    expect(ar-output('help').contains('db:check')).to.be-truthy;
  }

  it 'documents the generate subcommand', {
    expect(ar-output('help').contains('generate')).to.be-truthy;
  }

  it 'documents the destroy subcommand', {
    expect(ar-output('help').contains('destroy')).to.be-truthy;
  }

  it 'documents the schema tasks', {
    expect(ar-output('help').contains('db:schema:dump')).to.be-truthy;
  }

  it 'documents the runtime tasks', {
    expect(ar-output('help').contains('runner')).to.be-truthy;
  }
}

describe 'active-record runtime tasks', {
  it 'runs inline code', {
    expect(ar-output('runner', 'say 13 + 29').contains('42')).to.be-truthy;
  }

  it 'reports stats', {
    expect(ar-output('stats').contains('Migrations:')).to.be-truthy;
  }
}

my &db-group = $has-sqlite ?? &describe !! &xdescribe;

db-group 'active-record db: task routing', :tag<destructive>, {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  it 'reports a missing database as not ready', {
    with-temp-db(-> %env {
      expect(ar-exit(%env, 'db:check')).not.to.eq(0);
    });
  }

  it 'creates, migrates, checks, and resets a database', {
    with-temp-db(-> %env {
      aggregate-failures {
        expect(ar-exit(%env, 'db:create')).to.eq(0);
        expect(ar-exit(%env, 'db:migrate')).to.eq(0);
        expect(ar-exit(%env, 'db:check')).to.eq(0);
        expect(ar-exit(%env, 'db:reset')).to.eq(0);
      }
    });
  }

  it 'refuses a parallel reset without the confirmation flag', {
    with-temp-db(-> %env {
      expect(ar-exit(%env, 'db:reset', '--parallel=2')).to.eq(2);
    });
  }

  it 'creates, migrates, checks, and resets the parallel worker databases', {
    with-temp-db(-> %env {
      aggregate-failures {
        expect(ar-exit(%env, 'db:create', '--parallel=2')).to.eq(0);
        expect(ar-exit(%env, 'db:migrate', '--parallel=2')).to.eq(0);
        expect(ar-exit(%env, 'db:check', '--parallel=2')).to.eq(0);
        expect(ar-exit(%env, 'db:reset', '--parallel=2', '--yes')).to.eq(0);
      }
    });
  }
}

describe 'active-record generate migration', {
  it 'writes a migration file under db/migrate', {
    my $repo = $*CWD;
    my $tmp  = $*TMPDIR.add('ar-cli-generate-' ~ $*PID);
    $tmp.mkdir;

    LEAVE { run 'rm', '-rf', $tmp.Str }

    my $proc = run 'raku', '-I', $repo.add('lib').Str, $repo.add('bin/active-record').Str,
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
