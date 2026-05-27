use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $saved-url = %*ENV<DATABASE_URL>;
my $tmp = $*TMPDIR.add("ar-test-skip-spec-{$*PID}");

describe 'TestSkip helpers', {
  before-all {
    $tmp.mkdir unless $tmp.e;
  }

  after-all {
    for $tmp.dir { .unlink }
    $tmp.rmdir if $tmp.e;

    if $saved-url.defined {
      %*ENV<DATABASE_URL> = $saved-url;
    } else {
      %*ENV<DATABASE_URL>:delete;
    }
  }

  describe 'normalize-adapter-name', {
    it 'normalizes Postgres to pg', {
      expect(normalize-adapter-name('Postgres')).to.eq('pg');
    }

    it 'normalizes postgresql to pg', {
      expect(normalize-adapter-name('postgresql')).to.eq('pg');
    }

    it 'normalizes PG to pg', {
      expect(normalize-adapter-name('PG')).to.eq('pg');
    }

    it 'normalizes mysql2 to mysql', {
      expect(normalize-adapter-name('mysql2')).to.eq('mysql');
    }

    it 'normalizes MariaDB to mysql', {
      expect(normalize-adapter-name('MariaDB')).to.eq('mysql');
    }

    it 'normalizes sqlite3 to sqlite', {
      expect(normalize-adapter-name('sqlite3')).to.eq('sqlite');
    }
  }

  describe 'configured-adapter-name', {
    it 'returns undefined with no env and no config', {
      %*ENV<DATABASE_URL>:delete;

      expect(configured-adapter-name().defined).to.be-falsy;
    }

    it 'resolves DATABASE_URL=postgres://... to pg', {
      %*ENV<DATABASE_URL> = 'postgres://localhost/x';

      expect(configured-adapter-name()).to.eq('pg');
    }

    it 'resolves DATABASE_URL=mysql://... to mysql', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(configured-adapter-name()).to.eq('mysql');
    }

    it 'resolves DATABASE_URL=sqlite:... to sqlite', {
      %*ENV<DATABASE_URL> = 'sqlite::memory:';

      expect(configured-adapter-name()).to.eq('sqlite');
    }

    it 'resolves postgresql:// scheme to pg', {
      %*ENV<DATABASE_URL> = 'postgresql://u:p@h:5432/n';

      expect(configured-adapter-name()).to.eq('pg');
    }
  }

  describe 'adapter-matches', {
    it 'matches a single-string adapter', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter<mysql>)).to.be-truthy;
    }

    it 'returns False on single-string mismatch', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter<sqlite>)).to.be-falsy;
    }

    it 'matches a list containing the current adapter', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter<<mysql sqlite>>)).to.be-truthy;
    }

    it 'returns False for a list without the current adapter', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter<<sqlite pg>>)).to.be-falsy;
    }

    it 'normalizes user-supplied aliases', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter<MariaDB>)).to.be-truthy;
    }

    it 'is False when no adapter is configured', {
      %*ENV<DATABASE_URL>:delete;

      expect(adapter-matches(:adapter<pg>)).to.be-falsy;
    }

    it 'does not match pg when DATABASE_URL is mysql2://', {
      %*ENV<DATABASE_URL> = 'mysql2://localhost/x';

      expect(adapter-matches(:adapter<pg>)).to.be-falsy;
    }

    it 'matches mysql when DATABASE_URL is mysql2://', {
      %*ENV<DATABASE_URL> = 'mysql2://localhost/x';

      expect(adapter-matches(:adapter<mysql>)).to.be-truthy;
    }

    it 'returns False for an empty adapter list', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(adapter-matches(:adapter([]))).to.be-falsy;
    }
  }

  describe 'only-on', {
    it 'returns False without exiting when adapter matches', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(only-on(:adapter<mysql>)).to.eq(False);
    }

    it 'returns False without exiting when no adapter is configured', {
      %*ENV<DATABASE_URL>:delete;

      expect(only-on(:adapter<mysql>)).to.eq(False);
    }
  }

  describe 'skip-on', {
    it 'returns False without exiting when adapter does not match', {
      %*ENV<DATABASE_URL> = 'mysql://localhost/x';

      expect(skip-on(:adapter<sqlite>)).to.eq(False);
    }

    it 'returns False without exiting when no adapter is configured', {
      %*ENV<DATABASE_URL>:delete;

      expect(skip-on(:adapter<sqlite>)).to.eq(False);
    }
  }

  describe 'config file behavior', {
    it 'reads adapter from JSON config when :config-path is given', {
      my $cfg = $tmp.add('app.json');
      $cfg.spurt(q:to/JSON/);
      { "db": { "adapter": "sqlite", "name": ":memory:" } }
      JSON

      %*ENV<DATABASE_URL>:delete;

      expect(configured-adapter-name(:config-path($cfg.absolute))).to.eq('sqlite');

      $cfg.unlink if $cfg.e;
    }

    it 'lets DATABASE_URL take precedence over config file', {
      my $cfg = $tmp.add('app.json');
      $cfg.spurt(q:to/JSON/);
      { "db": { "adapter": "sqlite", "name": ":memory:" } }
      JSON

      %*ENV<DATABASE_URL> = 'postgres://localhost/x';

      expect(configured-adapter-name(:config-path($cfg.absolute))).to.eq('pg');

      $cfg.unlink if $cfg.e;
    }

    it 'normalizes adapter values read from the config file', {
      my $cfg = $tmp.add('app.json');
      $cfg.spurt(q:to/JSON/);
      { "db": { "adapter": "PostgreSQL", "name": "x" } }
      JSON

      %*ENV<DATABASE_URL>:delete;

      expect(configured-adapter-name(:config-path($cfg.absolute))).to.eq('pg');

      $cfg.unlink if $cfg.e;
    }

    it 'falls back to undefined when no env and no file are present', {
      my $cfg = $tmp.add('app.json');
      $cfg.unlink if $cfg.e;

      %*ENV<DATABASE_URL>:delete;

      expect(configured-adapter-name(:config-path($cfg.absolute)).defined).to.be-falsy;
    }

    it 'is ignored unless :config-path or :check-config is set', {
      my $cfg = $tmp.add('app.json');
      $cfg.spurt(q:to/JSON/);
      { "db": { "adapter": "sqlite", "name": ":memory:" } }
      JSON

      %*ENV<DATABASE_URL>:delete;

      expect(configured-adapter-name().defined).to.be-falsy;

      $cfg.unlink if $cfg.e;
    }
  }
}
