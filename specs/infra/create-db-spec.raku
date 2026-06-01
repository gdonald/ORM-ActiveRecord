use lib 'lib';
use BDD::Behave;
use JSON::Tiny;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Schema::WorkerDbs;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

sub table-names(Str:D $path) {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database($path));
  LEAVE { $h.dispose if $h.defined }
  $h.execute("SELECT name FROM sqlite_master WHERE type = 'table'").allrows.map(*[0]).Set;
}

my &group = $has-sqlite ?? &describe !! &xdescribe;

group 'ar create-db (sqlite via DATABASE_URL)', :tag<destructive>, {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  my @paths;
  after-all { .IO.unlink for @paths.grep(*.IO.e) }

  context 'single database', {
    my $p;

    before-all {
      if $has-sqlite {
        $p = $*TMPDIR.add("cdb-one-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
        @paths.push: $p;

        temp %*ENV<DATABASE_URL> = "sqlite:$p";
        create-test-databases();
        migrate-test-databases();
      }
    }

    it 'creates and migrates the one configured database', {
      expect(table-names($p){'users'}).to.be-truthy;
    }
  }

  context 'parallel per-worker copies', {
    my $base;
    my $cfg;
    my @suffixed;

    before-all {
      if $has-sqlite {
        $base = $*TMPDIR.add("cdb-par-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
        @suffixed = (^2).map: { apply-worker-suffix({ adapter => 'sqlite', name => $base }, $_)<name> };
        @paths.append: @suffixed;

        # parallel count comes from config (test env's `parallel`); the
        # connection itself is supplied via DATABASE_URL.
        $cfg = $*TMPDIR.add("cdb-par-cfg-{$*PID}-{(now * 1e6).Int}.json").Str;
        @paths.push: $cfg;
        $cfg.IO.spurt: to-json({
          test => { parallel => 2, primary => { adapter => 'sqlite', name => $base } },
        });

        temp %*ENV<DATABASE_URL> = "sqlite:$base";
        create-test-databases(:parallel, path => $cfg, env => 'test');
        migrate-test-databases(:parallel, path => $cfg, env => 'test');
      }
    }

    it 'creates and migrates the first worker copy', {
      expect(table-names(@suffixed[0]){'users'}).to.be-truthy;
    }

    it 'creates and migrates the second worker copy', {
      expect(table-names(@suffixed[1]){'users'}).to.be-truthy;
    }
  }

  context 'parallel defaults to the test environment', {
    my @suffixed;

    before-all {
      if $has-sqlite {
        my $base = $*TMPDIR.add("cdb-defenv-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
        @suffixed = (^2).map: { apply-worker-suffix({ adapter => 'sqlite', name => $base }, $_)<name> };
        @paths.append: @suffixed;

        # development has no parallel (1); only test has parallel => 2. With no
        # explicit env, :parallel must resolve to test — creating worker copy _1,
        # which a development resolution (count 1) would never produce.
        my $cfg = $*TMPDIR.add("cdb-defenv-cfg-{$*PID}-{(now * 1e6).Int}.json").Str;
        @paths.push: $cfg;
        $cfg.IO.spurt: to-json({
          development => { primary => { adapter => 'sqlite', name => $base } },
          test        => { parallel => 2, primary => { adapter => 'sqlite', name => $base } },
        });

        temp %*ENV<DATABASE_URL>;
        %*ENV<DATABASE_URL>:delete;
        create-test-databases(:parallel, path => $cfg);
      }
    }

    it 'creates worker copy _1 (proving the test env count was used)', {
      expect(@suffixed[1].IO.e).to.be-truthy;
    }
  }
}

describe 'DB.connection-names (multi-db vs single)', {
  my $tmp;

  after-each { $tmp.IO.unlink if $tmp && $tmp.IO.e }

  it 'lists every connection in a multi-db config', {
    $tmp = $*TMPDIR.add("cdb-multi-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({
      test => {
        primary   => { adapter => 'sqlite', name => 'db/p.sqlite3' },
        analytics => { adapter => 'sqlite', name => 'db/a.sqlite3' },
      },
    });

    expect(DB.connection-names(path => $tmp, env => 'test')).to.eq(<analytics primary>);
  }

  it 'returns just primary for a single-db config', {
    $tmp = $*TMPDIR.add("cdb-single-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({
      test => { primary => { adapter => 'sqlite', name => 'db/p.sqlite3' } },
    });

    expect(DB.connection-names(path => $tmp, env => 'test')).to.eq(("primary",));
  }

  it 'returns just primary for a legacy flat config', {
    $tmp = $*TMPDIR.add("cdb-legacy-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({ db => { adapter => 'sqlite', name => 'db/p.sqlite3' } });

    expect(DB.connection-names(path => $tmp, env => 'test')).to.eq(("primary",));
  }

  it 'excludes the parallel key from connection names', {
    $tmp = $*TMPDIR.add("cdb-par-key-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({
      test => { parallel => 4, primary => { adapter => 'sqlite', name => 'db/p.sqlite3' } },
    });

    expect(DB.connection-names(path => $tmp, env => 'test')).to.eq(("primary",));
  }
}

describe 'DB.env-parallel', {
  my $tmp;
  after-each { $tmp.IO.unlink if $tmp && $tmp.IO.e }

  it 'reads the test env parallel count', {
    $tmp = $*TMPDIR.add("ep-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({ test => { parallel => 8, primary => { adapter => 'sqlite', name => 'db/p.sqlite3' } } });

    expect(DB.env-parallel(path => $tmp, env => 'test')).to.eq(8);
  }

  it 'defaults to 1 when no parallel key is present', {
    $tmp = $*TMPDIR.add("ep1-{$*PID}-{(now * 1e6).Int}.json").Str;
    $tmp.IO.spurt: to-json({ development => { primary => { adapter => 'sqlite', name => 'db/p.sqlite3' } } });

    expect(DB.env-parallel(path => $tmp, env => 'development')).to.eq(1);
  }
}

group 'check-test-databases', :tag<destructive>, {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  my @paths;
  after-all { .IO.unlink for @paths.grep(*.IO.e) }

  it 'reports one problem per missing worker database', {
    my $base = $*TMPDIR.add("chk-miss-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    my $cfg  = $*TMPDIR.add("chk-miss-cfg-{$*PID}-{(now * 1e6).Int}.json").Str;
    @paths.push: $cfg;
    $cfg.IO.spurt: to-json({
      test => { parallel => 2, primary => { adapter => 'sqlite', name => $base } },
    });

    temp %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;

    expect(check-test-databases(:parallel, path => $cfg, env => 'test').elems).to.eq(2);
  }

  it 'reports no problems once databases are created and migrated', {
    my $base = $*TMPDIR.add("chk-ok-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    @paths.append: (^2).map: { apply-worker-suffix({ adapter => 'sqlite', name => $base }, $_)<name> };
    my $cfg = $*TMPDIR.add("chk-ok-cfg-{$*PID}-{(now * 1e6).Int}.json").Str;
    @paths.push: $cfg;
    $cfg.IO.spurt: to-json({
      test => { parallel => 2, primary => { adapter => 'sqlite', name => $base } },
    });

    temp %*ENV<DATABASE_URL> = "sqlite:$base";
    create-test-databases(:parallel, path => $cfg, env => 'test');
    migrate-test-databases(:parallel, path => $cfg, env => 'test');

    expect(check-test-databases(:parallel, path => $cfg, env => 'test').elems).to.eq(0);
  }

  it 'honors an explicit count over the config parallel key', {
    my $base = $*TMPDIR.add("chk-cnt-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    my $cfg  = $*TMPDIR.add("chk-cnt-cfg-{$*PID}-{(now * 1e6).Int}.json").Str;
    @paths.push: $cfg;
    # config says 4, but the explicit count of 2 must win: only 2 databases are
    # expected, so a fresh base yields 2 problems, not 4.
    $cfg.IO.spurt: to-json({
      test => { parallel => 4, primary => { adapter => 'sqlite', name => $base } },
    });

    temp %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;

    expect(check-test-databases(:parallel, count => 2, path => $cfg, env => 'test').elems).to.eq(2);
  }
}
