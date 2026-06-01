use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::Schema::Field;

%*ENV<DISABLE-SQL-LOG> = True;

sub current-adapter-name(--> Str) {
  return 'sqlite' without %*ENV<DATABASE_URL>;
  my %c = parse-database-url(%*ENV<DATABASE_URL>);
  given (%c<adapter> // '').lc {
    when 'pg' | 'postgres' | 'postgresql' { 'pg' }
    when 'mysql' | 'mysql2' | 'mariadb'   { 'mysql' }
    when 'sqlite' | 'sqlite3'             { 'sqlite' }
    default                                { 'sqlite' }
  }
}

my $is-mysql = current-adapter-name() eq 'mysql';

my %c = $is-mysql ?? parse-database-url(%*ENV<DATABASE_URL>) !! {};
my $host     = %c<host>     // 'localhost';
my $port     = (%c<port>    // 3306).Int;
my $user     = %c<user>     // 'root';
my $password = %c<password> // '';
my $database = %c<name>     // 'ar_test';

# Under behave --parallel, connect to this worker's own database so concurrent
# adapter specs don't collide on a shared base database's `widgets` table.
$database = apply-worker-suffix({ adapter => 'mysql', name => $database }, worker-index())<name>
  if per-worker-dbs-active();

my $can-connect = $is-mysql && (try {
  my $probe = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
  $probe.disconnect;
  True;
} // False);

describe 'MySqlAdapter direct integration', {
  if !$is-mysql {
    pending 'mysql-only';
  } elsif !$can-connect {
    pending "No reachable MySQL at $host:$port";
  } else {
    it 'connects from BUILD', {
      my $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      expect($mysql.is-connected).to.be-truthy;
      $mysql.disconnect;
    }

    it 'returns ? from bind-placeholder for n=1', {
      my $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      expect($mysql.bind-placeholder(1)).to.eq('?');
      $mysql.disconnect;
    }

    it 'returns ? from bind-placeholder for n=7', {
      my $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      expect($mysql.bind-placeholder(7)).to.eq('?');
      $mysql.disconnect;
    }

    it 'wraps identifiers in backticks', {
      my $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      expect($mysql.quote-identifier('foo')).to.eq('`foo`');
      $mysql.disconnect;
    }

    it 'doubles an embedded backtick in identifier quoting', {
      my $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      expect($mysql.quote-identifier('a`b')).to.eq('`a``b`');
      $mysql.disconnect;
    }
  }
}

describe 'MySqlAdapter ddl + introspection', {
  if !$is-mysql {
    pending 'mysql-only';
  } elsif !$can-connect {
    pending "No reachable MySQL at $host:$port";
  } else {
    my $mysql;
    my %types-by-name;

    before-each {
      $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      $mysql.exec('DROP TABLE IF EXISTS widgets');
      $mysql.ddl-create-table('widgets', [
        name   => { :string, limit => 64 },
        qty    => { :integer, default => 0 },
        active => { :boolean, default => True },
        body   => { :text },
      ]);
      $mysql.ddl-add-timestamps('widgets');

      my @fields = $mysql.get-fields(table => 'widgets');
      %types-by-name = @fields.map({ $_[0] => $_[1] });
    }

    after-each {
      if $mysql && $mysql.is-connected {
        $mysql.exec('DROP TABLE IF EXISTS widgets');
        $mysql.disconnect;
      }
    }

    it 'sees the id column via introspection', {
      expect(%types-by-name<id>:exists).to.be-truthy;
    }

    it 'normalizes id to integer', {
      expect(%types-by-name<id>).to.eq('integer');
    }

    it 'normalizes VARCHAR to character varying', {
      expect(%types-by-name<name>).to.eq('character varying');
    }

    it 'normalizes INT to integer', {
      expect(%types-by-name<qty>).to.eq('integer');
    }

    it 'normalizes TINYINT(1) to boolean', {
      expect(%types-by-name<active>).to.eq('boolean');
    }

    it 'preserves TEXT as text', {
      expect(%types-by-name<body>).to.eq('text');
    }

    it 'preserves DATETIME', {
      expect(%types-by-name<created_at>).to.eq('datetime');
    }

    it 'lists the new table via information_schema', {
      my @tables = $mysql.get-table-names;
      expect(('widgets' (elem) @tables).so).to.be-truthy;
    }
  }
}

describe 'MySqlAdapter build-insert / exec-stmt', {
  if !$is-mysql {
    pending 'mysql-only';
  } elsif !$can-connect {
    pending "No reachable MySQL at $host:$port";
  } else {
    my $mysql;
    my $id1;
    my $id2;
    my @field-objs;

    before-each {
      $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
      $mysql.exec('DROP TABLE IF EXISTS widgets');
      $mysql.ddl-create-table('widgets', [
        name   => { :string, limit => 64 },
        qty    => { :integer, default => 0 },
        active => { :boolean, default => True },
        body   => { :text },
      ]);
      $mysql.ddl-add-timestamps('widgets');

      my %types = name => 'VARCHAR', qty => 'INT', active => 'TINYINT(1)', body => 'TEXT';

      my $stmt = $mysql.build-insert(
        table => 'widgets',
        attrs => { name => 'alpha', qty => 3, active => True, body => 'lorem' },
        :%types,
      );
      $mysql.exec-stmt($stmt);
      $id1 = $mysql.exec('SELECT LAST_INSERT_ID()')[0][0].Int;

      my $stmt2 = $mysql.build-insert(
        table => 'widgets',
        attrs => { name => 'beta', qty => 7, active => False, body => 'ipsum' },
        :%types,
      );
      $mysql.exec-stmt($stmt2);
      $id2 = $mysql.exec('SELECT LAST_INSERT_ID()')[0][0].Int;

      @field-objs = $mysql.get-fields(table => 'widgets').map({
        Field.new(name => $_[0], type => $_[1]);
      });
    }

    after-each {
      if $mysql && $mysql.is-connected {
        $mysql.exec('DROP TABLE IF EXISTS widgets');
        $mysql.disconnect;
      }
    }

    it 'uses ? placeholders rather than $N in INSERT', {
      my %types = name => 'VARCHAR', qty => 'INT', active => 'TINYINT(1)', body => 'TEXT';
      my $stmt = $mysql.build-insert(
        table => 'widgets',
        attrs => { name => 'check', qty => 1, active => True, body => 'x' },
        :%types,
      );
      expect($stmt.sql.contains('?')).to.be-truthy;
    }

    it 'omits RETURNING from INSERT (MySQL has no RETURNING)', {
      my %types = name => 'VARCHAR', qty => 'INT', active => 'TINYINT(1)', body => 'TEXT';
      my $stmt = $mysql.build-insert(
        table => 'widgets',
        attrs => { name => 'check', qty => 1, active => True, body => 'x' },
        :%types,
      );
      expect($stmt.sql.contains('RETURNING')).to.be-falsy;
    }

    it 'assigns a positive surrogate id via LAST_INSERT_ID()', {
      expect($id1).to.be-greater-than(0);
    }

    it 'advances AUTO_INCREMENT by one', {
      expect($id2).to.eq($id1 + 1);
    }

    it 'coerces TINYINT(1) back to Bool through the boolean label', {
      my $row = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<active>).to.be-a(Bool);
    }

    it 'preserves True on round-trip', {
      my $row = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<active>).to.eq(True);
    }

    it 'preserves an integer round-trip as Int value', {
      my $row = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<qty>).to.eq(3);
    }

    it 'preserves a string round-trip', {
      my $row = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<name>).to.eq('alpha');
    }

    it 'preserves False on round-trip', {
      my $row2 = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id2 },
      );
      expect($row2<active>).to.eq(False);
    }

    it 'coerces CURRENT_TIMESTAMP default to DateTime', {
      my $row = $mysql.get-record(
        table  => 'widgets',
        fields => @field-objs,
        where  => { id => $id1 },
      );
      expect($row<created_at>).to.be-a(DateTime);
    }

    it 'binds value plus id (2 binds) in build-update', {
      my $now = DateTime.new('2026-05-09T12:34:56Z');
      my $dt-stmt = $mysql.build-update(
        :table('widgets'),
        :id($id1),
        attrs => { created_at => $now },
        types => { created_at => 'DATETIME' },
      );
      expect($dt-stmt.binds.elems).to.eq(2);
    }

    it 'reports the affected row count from delete-records', {
      my $deleted = $mysql.delete-records(table => 'widgets', where => { id => $id1 });
      expect($deleted).to.eq(1);
    }

    it 'leaves one row remaining after deleting id1', {
      $mysql.delete-records(table => 'widgets', where => { id => $id1 });
      my @remaining = $mysql.get-records(
        table  => 'widgets',
        fields => @field-objs,
      );
      expect(@remaining.elems).to.eq(1);
    }
  }
}

describe 'MySqlAdapter disconnect / reconnect', {
  if !$is-mysql {
    pending 'mysql-only';
  } elsif !$can-connect {
    pending "No reachable MySQL at $host:$port";
  } else {
    my $mysql;

    before-each {
      $mysql = MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database);
    }

    after-each {
      $mysql.disconnect if $mysql && $mysql.is-connected;
    }

    it 'returns truthy from disconnect when a handle existed', {
      expect($mysql.disconnect).to.be-truthy;
    }

    it 'reports false from is-connected after disconnect', {
      $mysql.disconnect;
      expect($mysql.is-connected).to.be-falsy;
    }

    it 're-establishes the connection on reconnect', {
      $mysql.disconnect;
      $mysql.reconnect;
      expect($mysql.is-connected).to.be-truthy;
    }
  }
}
