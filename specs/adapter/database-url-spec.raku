use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::DB;

describe 'parse-database-url', {
  context 'postgres:// with full authority and query', {
    my %pg = parse-database-url('postgres://alice:secret@db.example.com:5433/myapp?schema=public&sslmode=require');

    it 'maps postgres:// to adapter pg', {
      expect(%pg<adapter>).to.eq('pg');
    }

    it 'parses the user', {
      expect(%pg<user>).to.eq('alice');
    }

    it 'parses the password', {
      expect(%pg<password>).to.eq('secret');
    }

    it 'parses the host', {
      expect(%pg<host>).to.eq('db.example.com');
    }

    it 'parses the port as an Int value', {
      expect(%pg<port>).to.eq(5433);
    }

    it 'parses the port as an Int type', {
      expect(%pg<port>).to.be-a(Int);
    }

    it 'parses the database name', {
      expect(%pg<name>).to.eq('myapp');
    }

    it 'preserves the schema query param', {
      expect(%pg<schema>).to.eq('public');
    }

    it 'preserves a second query param', {
      expect(%pg<sslmode>).to.eq('require');
    }
  }

  context 'postgresql:// alias', {
    it 'maps to adapter pg', {
      expect(parse-database-url('postgresql://h/db')<adapter>).to.eq('pg');
    }
  }

  context 'host-only / no auth / no port', {
    my %hp = parse-database-url('postgres://localhost/foo');

    it 'parses the plain host', {
      expect(%hp<host>).to.eq('localhost');
    }

    it 'parses the database name', {
      expect(%hp<name>).to.eq('foo');
    }

    it 'omits port when not given', {
      expect(%hp<port>:exists).to.be-falsy;
    }

    it 'omits user when not given', {
      expect(%hp<user>:exists).to.be-falsy;
    }

    it 'omits password when not given', {
      expect(%hp<password>:exists).to.be-falsy;
    }
  }

  context 'empty authority (unix socket / local)', {
    my %loc = parse-database-url('postgres:///mydb');

    it 'parses the database with empty authority', {
      expect(%loc<name>).to.eq('mydb');
    }

    it 'has no host for empty authority', {
      expect(%loc<host>:exists).to.be-falsy;
    }
  }

  context 'port without user', {
    my %po = parse-database-url('postgres://h:6543/db');

    it 'parses the host', {
      expect(%po<host>).to.eq('h');
    }

    it 'parses the port-only authority', {
      expect(%po<port>).to.eq(6543);
    }
  }

  context 'percent-decoding', {
    it 'decodes the password', {
      expect(parse-database-url('postgres://u:p%40ss@h/db')<password>).to.eq('p@ss');
    }

    it 'decodes the user', {
      expect(parse-database-url('postgres://u%2Bv@h/db')<user>).to.eq('u+v');
    }
  }

  context 'mysql family', {
    my %my = parse-database-url('mysql://root@127.0.0.1/ar_test');

    it 'maps mysql:// to adapter mysql', {
      expect(%my<adapter>).to.eq('mysql');
    }

    it 'parses the mysql user', {
      expect(%my<user>).to.eq('root');
    }

    it 'parses the mysql host', {
      expect(%my<host>).to.eq('127.0.0.1');
    }

    it 'parses the mysql database', {
      expect(%my<name>).to.eq('ar_test');
    }

    it 'omits password when not given', {
      expect(%my<password>:exists).to.be-falsy;
    }

    it 'maps mysql2:// alias to mysql', {
      expect(parse-database-url('mysql2://root@h/db')<adapter>).to.eq('mysql');
    }

    it 'maps mariadb:// alias to mysql', {
      expect(parse-database-url('mariadb://root@h/db')<adapter>).to.eq('mysql');
    }
  }

  context 'sqlite forms', {
    it 'maps sqlite::memory: to adapter sqlite', {
      expect(parse-database-url('sqlite::memory:')<adapter>).to.eq('sqlite');
    }

    it 'preserves the :memory: literal as database', {
      expect(parse-database-url('sqlite::memory:')<database>).to.eq(':memory:');
    }

    it 'preserves a sqlite relative path', {
      expect(parse-database-url('sqlite:db/test.sqlite')<database>).to.eq('db/test.sqlite');
    }

    it 'preserves a sqlite ./relative path', {
      expect(parse-database-url('sqlite:./local.db')<database>).to.eq('./local.db');
    }

    it 'preserves a sqlite:/// absolute path', {
      expect(parse-database-url('sqlite:///srv/data/app.db')<database>).to.eq('/srv/data/app.db');
    }

    it 'maps sqlite3:// alias to sqlite', {
      expect(parse-database-url('sqlite3:foo.db')<adapter>).to.eq('sqlite');
    }
  }

  context 'error cases', {
    it 'dies on a URL without a scheme separator', {
      expect({ parse-database-url('not-a-url') }).to.raise-error;
    }

    it 'dies on an unsupported scheme', {
      expect({ parse-database-url('mongo://h/db') }).to.raise-error;
    }

    it 'dies on the redis scheme', {
      expect({ parse-database-url('redis://h:6379') }).to.raise-error;
    }
  }
}

describe 'DB.read-config with DATABASE_URL', {
  it 'honours DATABASE_URL for the adapter', {
    temp %*ENV<DATABASE_URL> = 'sqlite::memory:';
    my %c = DB.read-config;
    expect(%c<adapter>).to.eq('sqlite');
  }

  it 'carries the database from the URL', {
    temp %*ENV<DATABASE_URL> = 'sqlite::memory:';
    my %c = DB.read-config;
    expect(%c<database>).to.eq(':memory:');
  }
}
