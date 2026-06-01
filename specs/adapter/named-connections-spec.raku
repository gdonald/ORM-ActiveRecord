use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Sqlite;

%*ENV<DISABLE-SQL-LOG> = True;

# These specs assert base read-config output, so neutralize any per-worker
# overlay the parallel test harness may have exported into this worker.
%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;

sub fresh-tmp() {
  $*TMPDIR.add("ar-named-conn-{$*PID}-{(now * 1000).Int}.json");
}

describe 'DB.read-config named connections', {
  my $tmp;
  my $saved-url;

  before-each {
    $saved-url = %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;

    $tmp = fresh-tmp();
    $tmp.spurt: q:to/JSON/;
{
  "test": {
    "primary":   { "adapter": "pg", "name": "ar_test" },
    "analytics": { "adapter": "pg", "name": "ar_analytics_test" }
  },
  "development": {
    "primary": { "adapter": "pg", "name": "ar_dev" }
  }
}
JSON
  }

  after-each {
    $tmp.unlink if $tmp && $tmp.e;
    %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
  }

  it 'returns the primary connection of the active env', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'test')<name>)
      .to.eq('ar_test');
  }

  it 'returns a non-primary named connection', {
    expect(DB.read-config(path => $tmp.Str, name => 'analytics', env => 'test')<name>)
      .to.eq('ar_analytics_test');
  }

  it 'selects connections from the requested environment', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'development')<name>)
      .to.eq('ar_dev');
  }

  it 'returns an empty config for an unknown connection name', {
    expect(DB.read-config(path => $tmp.Str, name => 'nope', env => 'test').elems)
      .to.eq(0);
  }

  context 'when DATABASE_URL is set', {
    it 'overrides the primary connection', {
      %*ENV<DATABASE_URL> = 'postgres://u@localhost/from_url';

      expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'test')<name>)
        .to.eq('from_url');
    }

    it 'still resolves non-primary connections from the file', {
      %*ENV<DATABASE_URL> = 'postgres://u@localhost/from_url';

      expect(DB.read-config(path => $tmp.Str, name => 'analytics', env => 'test')<name>)
        .to.eq('ar_analytics_test');
    }
  }
}

describe 'DB.read-config legacy flat config', {
  my $tmp;
  my $saved-url;

  before-each {
    $saved-url = %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;

    $tmp = fresh-tmp();
    $tmp.spurt: q:to/JSON/;
{
  "db": { "adapter": "sqlite", "name": "db/legacy.sqlite3" }
}
JSON
  }

  after-each {
    $tmp.unlink if $tmp && $tmp.e;
    %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
  }

  it 'promotes the flat db block to the primary connection', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'test')<name>)
      .to.eq('db/legacy.sqlite3');
  }

  it 'has no non-primary connections', {
    expect(DB.read-config(path => $tmp.Str, name => 'analytics', env => 'test').elems)
      .to.eq(0);
  }
}

describe 'DB.shared keyed by connection name', {
  it 'returns distinct instances per name', {
    my $a = DB.new(adapter => SqliteAdapter.new(database => ':memory:'));
    my $b = DB.new(adapter => SqliteAdapter.new(database => ':memory:'));

    DB.set-shared($a, name => 'primary');
    DB.set-shared($b, name => 'analytics');

    LEAVE {
      DB.set-shared(Nil, name => 'primary');
      DB.set-shared(Nil, name => 'analytics');
    }

    aggregate-failures {
      expect(DB.shared(name => 'primary') === $a).to.be-truthy;
      expect(DB.shared(name => 'analytics') === $b).to.be-truthy;
    }
  }
}
