use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

sub adapter-kind(--> Str) {
  my $a = DB.shared.adapter;
  return 'none' without $a;
  given $a.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

my $is-pg = adapter-kind() eq 'pg';

# Resolve the live primary connection before clearing the worker env below. The
# per-environment config tests need a clean env, but the PostgreSQL connection
# test must still reach the same (test) database rather than falling through to
# the development environment.
my %primary-config = DB.read-config(name => 'primary');

%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;

sub fresh-tmp() {
  $*TMPDIR.add("ar-config-extras-{$*PID}-{(now * 1000).Int}.json");
}

describe 'per-environment config', {
  my $tmp;
  my $saved-url;

  before-each {
    $saved-url = %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;
    $tmp = fresh-tmp();
    $tmp.spurt: q:to/JSON/;
{
  "development": { "primary": { "adapter": "pg", "name": "app_dev" } },
  "test":        { "primary": { "adapter": "pg", "name": "app_test" } },
  "production":  { "primary": { "adapter": "pg", "name": "app_prod" } }
}
JSON
  }

  after-each {
    $tmp.unlink if $tmp && $tmp.e;
    %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
  }

  it 'reads the development environment', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'development')<name>).to.eq('app_dev');
  }

  it 'reads the production environment', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'production')<name>).to.eq('app_prod');
  }
}

describe 'connection options in config', {
  my $tmp;
  my $saved-url;

  before-each {
    $saved-url = %*ENV<DATABASE_URL>;
    %*ENV<DATABASE_URL>:delete;
    $tmp = fresh-tmp();
    $tmp.spurt: q:to/JSON/;
{
  "production": {
    "primary": {
      "adapter": "pg", "name": "app_prod", "host": "db",
      "sslmode": "require", "sslrootcert": "/etc/ssl/ca.pem",
      "application_name": "myapp"
    }
  }
}
JSON
  }

  after-each {
    $tmp.unlink if $tmp && $tmp.e;
    %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
  }

  it 'preserves sslmode', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'production')<sslmode>).to.eq('require');
  }

  it 'preserves sslrootcert', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'production')<sslrootcert>).to.eq('/etc/ssl/ca.pem');
  }

  it 'preserves application_name', {
    expect(DB.read-config(path => $tmp.Str, name => 'primary', env => 'production')<application_name>).to.eq('myapp');
  }
}

describe 'connection options in DATABASE_URL', {
  my $saved-url;
  before-each { $saved-url = %*ENV<DATABASE_URL>; }
  after-each  { $saved-url.defined ?? (%*ENV<DATABASE_URL> = $saved-url) !! (%*ENV<DATABASE_URL>:delete); }

  it 'preserves application_name from the query string', {
    %*ENV<DATABASE_URL> = 'postgres://u@h:5432/db?sslmode=require&application_name=myapp';
    expect(DB.read-config(name => 'primary')<application_name>).to.eq('myapp');
  }
}

describe 'per-connection migration path', {
  it 'uses an explicit migration-path', {
    expect(Migrate.new(args => [], migration-path => 'custom/migrate').migration-path).to.eq('custom/migrate');
  }

  it 'defaults to db/migrate when none is configured', {
    expect(Migrate.new(args => []).migration-path).to.eq('db/migrate');
  }
}

my &pg-it = $is-pg ?? &it !! &xit;

describe 'PostgreSQL connection options take effect', :tag<destructive>, {
  pg-it 'sets the session application_name and accepts an ssl mode', {
    my %c = %primary-config;
    my $pg = PgAdapter.new(
      schema           => %c<schema> // 'public',
      host             => %c<host> // 'localhost',
      database         => %c<name> // %c<database>,
      user             => %c<user> // '',
      password         => %c<password> // '',
      sslmode          => 'disable',
      application-name => 'ar-cfg-test',
    );
    LEAVE { $pg.disconnect if $pg && $pg.is-connected }
    my @rows = $pg.exec('SELECT application_name FROM pg_stat_activity WHERE pid = pg_backend_pid()');
    expect(@rows[0][0].Str).to.eq('ar-cfg-test');
  }
}
