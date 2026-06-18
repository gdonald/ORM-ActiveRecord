use lib 'lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Testing::Fixtures;
use ORM::ActiveRecord::Testing::DatabaseCleaner;
use ORM::ActiveRecord::Testing::Transaction;

%*ENV<DISABLE-SQL-LOG> = True;

sub fresh(--> Hash) {
  my $stamp  = "{$*PID}-{(now * 1e6).Int}";
  my $dbfile = $*TMPDIR.add("helpers-spec-$stamp.sqlite3").Str;
  my $fixdir = $*TMPDIR.add("helpers-spec-fix-$stamp");
  $fixdir.mkdir;

  $fixdir.add('authors.yml').spurt: q:to/YML/;
  alice:
    name: Alice
    admin: <%= True %>
  bob:
    name: Bob
  YML

  $fixdir.add('posts.yml').spurt: q:to/YML/;
  hello:
    title: Hello World
    author: alice
  YML

  %*ENV<BEHAVE_WORKER_INDEX>:delete;
  %*ENV<BEHAVE_WORKER_COUNT>:delete;
  %*ENV<DATABASE_URL> = "sqlite:$dbfile";
  DB.set-shared(Nil);

  my $adapter = DB.shared.adapter;
  $adapter.ddl-create-table('authors', [ name => { :string, limit => 32 }, admin => { :boolean } ]);
  $adapter.ddl-create-table('posts',   [ title => { :string, limit => 64 }, author_id => { :integer } ]);

  { dbfile => $dbfile, fixdir => $fixdir, adapter => $adapter };
}

sub cleanup(%env) {
  %env<dbfile>.IO.unlink if %env<dbfile>.IO.e;
  run 'rm', '-rf', %env<fixdir>.Str;
}

sub query(Str:D $dbfile, Str:D $sql) {
  my $h = DBIish.connect('SQLite', :database($dbfile));
  LEAVE { $h.dispose if $h.defined }
  $h.execute($sql).allrows.map(*.Array).eager;
}

describe 'test helpers', {
  context 'fixture loader', {
    it 'loads labelled rows with deterministic, reference-resolving ids', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      my $fx = Fixtures.new(dir => %env<fixdir>.Str).load;

      aggregate-failures {
        expect(query(%env<dbfile>, "SELECT count(*) FROM authors")[0][0]).to.eq(2);
        expect($fx.id('authors', 'alice')).to.eq(Fixtures.new.identify('alice'));
        expect(query(%env<dbfile>, "SELECT admin FROM authors WHERE name = 'Alice'")[0][0]).to.eq(1);
        expect(query(%env<dbfile>, "SELECT author_id FROM posts WHERE title = 'Hello World'")[0][0]).to.eq($fx.id('authors', 'alice'));
      }
    }
  }

  context 'database cleaner', {
    it 'empties every table with the deletion strategy', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      Fixtures.new(dir => %env<fixdir>.Str).load;
      DatabaseCleaner.new.clean(strategy => 'deletion');

      aggregate-failures {
        expect(query(%env<dbfile>, "SELECT count(*) FROM authors")[0][0]).to.eq(0);
        expect(query(%env<dbfile>, "SELECT count(*) FROM posts")[0][0]).to.eq(0);
      }
    }
  }

  context 'transactional wrapper', {
    it 'rolls back everything written inside it', {
      my %env = fresh;
      LEAVE { cleanup(%env) }

      with-rollback {
        %env<adapter>.exec("INSERT INTO authors (id, name) VALUES (42, 'Rolled')");
      };

      expect(query(%env<dbfile>, "SELECT count(*) FROM authors WHERE id = 42")[0][0]).to.eq(0);
    }
  }
}
