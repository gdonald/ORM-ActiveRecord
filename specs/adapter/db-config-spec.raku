use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::Adapter::MySql;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'DB.adapter-class-for', {
  context 'postgres family', {
    it 'maps adapter pg to PgAdapter', {
      expect(DB.adapter-class-for({adapter => 'pg'})).to.eq(PgAdapter);
    }

    it 'maps adapter postgres to PgAdapter', {
      expect(DB.adapter-class-for({adapter => 'postgres'})).to.eq(PgAdapter);
    }

    it 'maps adapter postgresql to PgAdapter', {
      expect(DB.adapter-class-for({adapter => 'postgresql'})).to.eq(PgAdapter);
    }

    it 'treats adapter name as case-insensitive', {
      expect(DB.adapter-class-for({adapter => 'PG'})).to.eq(PgAdapter);
    }
  }

  context 'sqlite family', {
    it 'maps adapter sqlite to SqliteAdapter', {
      expect(DB.adapter-class-for({adapter => 'sqlite'})).to.eq(SqliteAdapter);
    }

    it 'maps adapter sqlite3 to SqliteAdapter', {
      expect(DB.adapter-class-for({adapter => 'sqlite3'})).to.eq(SqliteAdapter);
    }
  }

  context 'mysql family', {
    it 'maps adapter mysql to MySqlAdapter', {
      expect(DB.adapter-class-for({adapter => 'mysql'})).to.eq(MySqlAdapter);
    }

    it 'maps adapter mysql2 to MySqlAdapter', {
      expect(DB.adapter-class-for({adapter => 'mysql2'})).to.eq(MySqlAdapter);
    }

    it 'maps adapter mariadb to MySqlAdapter', {
      expect(DB.adapter-class-for({adapter => 'mariadb'})).to.eq(MySqlAdapter);
    }
  }

  context 'defaults', {
    it 'defaults an empty config to PgAdapter', {
      expect(DB.adapter-class-for({})).to.eq(PgAdapter);
    }

    it 'defaults to PgAdapter when adapter key is missing', {
      expect(DB.adapter-class-for({host => 'h', name => 'foo'})).to.eq(PgAdapter);
    }
  }

  context 'unknown adapters', {
    it 'dies on an unknown adapter name', {
      expect({ DB.adapter-class-for({adapter => 'mongo'}) }).to.raise-error;
    }

    it 'names the bad adapter in the error message', {
      my $msg;
      try {
        DB.adapter-class-for({adapter => 'redis'});
        CATCH { default { $msg = .message } }
      }
      expect($msg).to.match(/'redis'/);
    }
  }
}

describe 'DB.read-config(:path)', {
  sub fresh-tmp() {
    $*TMPDIR.add("ar-config-spec-{$*PID}-{(now * 1000).Int}.json");
  }

  context 'with a sqlite JSON config', {
    my $tmp;
    my $saved-url;

    before-each {
      $saved-url = %*ENV<DATABASE_URL>;
      %*ENV<DATABASE_URL>:delete;

      $tmp = fresh-tmp();
      $tmp.spurt: q:to/JSON/;
{
  "db": {
    "adapter": "sqlite",
    "name": ":memory:"
  }
}
JSON
    }

    after-each {
      $tmp.unlink if $tmp && $tmp.e;
      %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
    }

    it 'parses the adapter', {
      my %c = DB.read-config(path => $tmp.Str);
      expect(%c<adapter>).to.eq('sqlite');
    }

    it 'parses the name', {
      my %c = DB.read-config(path => $tmp.Str);
      expect(%c<name>).to.eq(':memory:');
    }

    it 'drives adapter selection from the JSON', {
      my %c = DB.read-config(path => $tmp.Str);
      expect(DB.adapter-class-for(%c)).to.eq(SqliteAdapter);
    }
  }

  context 'with a mysql JSON config', {
    my $tmp;
    my $saved-url;

    before-each {
      $saved-url = %*ENV<DATABASE_URL>;
      %*ENV<DATABASE_URL>:delete;

      $tmp = fresh-tmp();
      $tmp.spurt: q:to/JSON/;
{
  "db": {
    "adapter": "mysql",
    "host": "db.internal",
    "port": 3307,
    "name": "shop",
    "user": "app",
    "password": "s3cret"
  }
}
JSON
    }

    after-each {
      $tmp.unlink if $tmp && $tmp.e;
      %*ENV<DATABASE_URL> = $saved-url if $saved-url.defined;
    }

    it 'parses the mysql adapter', {
      my %m = DB.read-config(path => $tmp.Str);
      expect(%m<adapter>).to.eq('mysql');
    }

    it 'parses the host', {
      my %m = DB.read-config(path => $tmp.Str);
      expect(%m<host>).to.eq('db.internal');
    }

    it 'parses the port', {
      my %m = DB.read-config(path => $tmp.Str);
      expect(%m<port>).to.eq(3307);
    }

    it 'parses the name', {
      my %m = DB.read-config(path => $tmp.Str);
      expect(%m<name>).to.eq('shop');
    }

    it 'drives MySqlAdapter selection from the JSON', {
      my %m = DB.read-config(path => $tmp.Str);
      expect(DB.adapter-class-for(%m)).to.eq(MySqlAdapter);
    }
  }

  context 'when DATABASE_URL is also set', {
    my $tmp;
    my $saved-url;

    before-each {
      $saved-url = %*ENV<DATABASE_URL>;

      $tmp = fresh-tmp();
      $tmp.spurt: q:to/JSON/;
{
  "db": {
    "adapter": "mysql",
    "host": "db.internal",
    "port": 3307,
    "name": "shop"
  }
}
JSON
    }

    after-each {
      $tmp.unlink if $tmp && $tmp.e;
      if $saved-url.defined {
        %*ENV<DATABASE_URL> = $saved-url;
      } else {
        %*ENV<DATABASE_URL>:delete;
      }
    }

    it 'overrides on-disk JSON with DATABASE_URL', {
      %*ENV<DATABASE_URL> = 'sqlite::memory:';
      my %u = DB.read-config(path => $tmp.Str);
      expect(%u<adapter>).to.eq('sqlite');
    }
  }
}
