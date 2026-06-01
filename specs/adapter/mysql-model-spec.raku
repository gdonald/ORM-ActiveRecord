use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::DatabaseUrl;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::Adapter::MySql;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

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

my $mysql       = $is-mysql ?? (try MySqlAdapter.new(:$host, :$port, :$user, :$password, :$database)) !! Nil;
my $can-connect = $is-mysql && $mysql.defined && $mysql.is-connected;

class Widget is Model {
  submethod BUILD {
    self.validate: 'name', { :presence }
  }
}

my &group = $can-connect ?? &describe !! &xdescribe;

group "MySqlAdapter-backed Model", :tag<destructive>, {
  my $saved-shared;

  before-all {
    $saved-shared = DB.shared;
    DB.set-shared(DB.new(adapter => $mysql));
    $mysql.exec('DROP TABLE IF EXISTS widgets');
    $mysql.ddl-create-table('widgets', [
      name   => { :string, limit => 64 },
      qty    => { :integer, default => 0 },
      active => { :boolean, default => True },
    ]);
    $mysql.ddl-add-timestamps('widgets');
  }

  after-all {
    $mysql.exec('DROP TABLE IF EXISTS widgets');
    DB.set-shared($saved-shared);
  }

  before-each { Widget.destroy-all }
  after-each  { Widget.destroy-all }

  context 'create + find', {
    it 'returns a surrogate id from LAST_INSERT_ID()', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.id).to.be-truthy;
    }

    it 'persists the name', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.name).to.eq('Alpha');
    }

    it 'persists the qty', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.qty).to.eq(3);
    }

    it 'persists active as True', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      expect($w.active).to.eq(True);
    }

    it 'round-trips the name via find', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = Widget.find($w.id);
      expect($found.name).to.eq('Alpha');
    }

    it 'reads active back as Bool through information_schema introspection', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = Widget.find($w.id);
      expect($found.active).to.be-a(Bool);
    }

    it 'preserves active value on read', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = Widget.find($w.id);
      expect($found.active).to.eq(True);
    }

    it 'reads created_at back as DateTime', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      my $found = Widget.find($w.id);
      expect($found.created_at).to.be-a(DateTime);
    }
  }

  context 'update with Bool = False', {
    it 'preserves the False after update', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      my $reloaded = Widget.find($w.id);
      expect($reloaded.active).to.eq(False);
    }

    it 'updates qty', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      my $reloaded = Widget.find($w.id);
      expect($reloaded.qty).to.eq(9);
    }
  }

  context 'where / count / find-by (Alpha updated to False before Beta/Gamma)', {
    before-each {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      Widget.create({ name => 'Beta',  qty => 1, active => False });
      Widget.create({ name => 'Gamma', qty => 5, active => True });
    }

    it 'counts three rows after three inserts', {
      expect(Widget.count).to.eq(3);
    }

    it 'narrows where(active => True) to one row', {
      expect(Widget.where({ active => True }).count).to.eq(1);
    }

    it 'narrows where(active => False) to two rows', {
      expect(Widget.where({ active => False }).count).to.eq(2);
    }

    it 'hits the right row via find-by', {
      my $by-name = Widget.find-by({ name => 'Gamma' });
      expect($by-name.qty).to.eq(5);
    }
  }

  context 'destroy', {
    it 'removes exactly one row via destroy', {
      my $w = Widget.create({ name => 'Alpha', qty => 3, active => True });
      $w.update({ active => False, qty => 9 });
      Widget.create({ name => 'Beta',  qty => 1, active => False });
      Widget.create({ name => 'Gamma', qty => 5, active => True });

      my $by-name = Widget.find-by({ name => 'Gamma' });
      $by-name.destroy;

      expect(Widget.count).to.eq(2);
    }

    it 'clears the table via destroy-all', {
      Widget.create({ name => 'Alpha', qty => 3, active => True });
      Widget.create({ name => 'Beta',  qty => 1, active => False });

      Widget.destroy-all;

      expect(Widget.count).to.eq(0);
    }
  }
}
