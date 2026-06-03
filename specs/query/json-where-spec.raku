use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Relation::Query::Json;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub adapter-kind(--> Str) {
  return 'none' without $adapter;
  given $adapter.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

my $kind      = adapter-kind();
my $is-pg     = $kind eq 'pg';
my $is-mysql  = $kind eq 'mysql';
my $is-sqlite = $kind eq 'sqlite';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub cleanup-tables {
  try { $adapter.ddl-drop-table('_jw') if table-exists('_jw') }
}

# Run a SELECT built from the adapter's WHERE builder; return matched ids.
sub matched-ids(%where, %where-not = {} --> Str) {
  my $stmt = SqlStmt.new(:adapter($adapter));
  my $w = $adapter.build-where($stmt, %where, %where-not);
  $stmt.sql = 'SELECT id FROM _jw' ~ ($w ?? " WHERE $w" !! '') ~ ' ORDER BY id';
  $adapter.exec-stmt($stmt).map({ $_[0].Int }).join(',');
}

class CreateJw is Migration {
  method change {
    self.create-table: '_jw', [ data => { :jsonb } ];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

my &pg-mysql-it = ($is-pg || $is-mysql) ?? &it !! &xit;
my &sqlite-it   = $is-sqlite             ?? &it !! &xit;

group 'where with JSON predicate operators', :order<defined>, {
  before-all {
    cleanup-tables;
    CreateJw.new.up;
    $adapter.exec(q{INSERT INTO _jw (data) VALUES ('{"theme":"dark","level":"5"}')});
    $adapter.exec(q{INSERT INTO _jw (data) VALUES ('{"theme":"light"}')});
  }
  after-all { cleanup-tables }

  context 'path extraction (->>)', :order<defined>, {
    it 'matches text equality at a path', {
      expect(matched-ids({ data => JsonPredicate.extract('theme').eq('dark') })).to.eq('1');
    }

    it 'matches the complement with ne', {
      expect(matched-ids({ data => JsonPredicate.extract('theme').ne('dark') })).to.eq('2');
    }

    it 'inverts an extraction under where.not', {
      expect(matched-ids({}, { data => JsonPredicate.extract('theme').eq('dark') })).to.eq('2');
    }
  }

  context 'containment', :order<defined>, {
    pg-mysql-it 'matches a contained object', {
      expect(matched-ids({ data => JsonPredicate.contains({ theme => 'dark' }) })).to.eq('1');
    }

    sqlite-it 'is unsupported on SQLite', {
      expect({ matched-ids({ data => JsonPredicate.contains({ theme => 'dark' }) }) }).to.raise-error;
    }
  }

  context 'key existence', :order<defined>, {
    pg-mysql-it 'matches rows that have the key', {
      expect(matched-ids({ data => JsonPredicate.has-key('level') })).to.eq('1');
    }

    sqlite-it 'is unsupported on SQLite', {
      expect({ matched-ids({ data => JsonPredicate.has-key('level') }) }).to.raise-error;
    }
  }
}
