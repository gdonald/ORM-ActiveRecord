use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Connection::Registry;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  my $handle = DBIish.connect('SQLite', :database(':memory:'));
  $handle.dispose;
  True;
} // False;

class RegistryGadget is Model {}
GLOBAL::<RegistryGadget> := RegistryGadget;

class RegistryWidget is Model {
  submethod BUILD {
    self.has-many: gadgets => %(class-name => 'RegistryGadget', foreign-key => 'registry_widget_id');
  }
}
GLOBAL::<RegistryWidget> := RegistryWidget;

my &group = $has-sqlite ?? &describe !! &xdescribe;

group 'Connection::Registry (sqlite via DATABASE_URL)', :tag<destructive>, {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  my $dbfile;
  my $saved-url;
  my $saved-shared;
  my $name;

  before-all {
    # Act on the base connection, clear of any harness worker overlay.
    %*ENV<BEHAVE_WORKER_INDEX>:delete;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    $saved-shared = DB.shared;
    $saved-url    = %*ENV<DATABASE_URL>;

    # A file-backed database (not :memory:) so every pooled connection opens the
    # same schema and data — the registry checks connections out of the pool.
    $dbfile = $*TMPDIR.add("registry-spec-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
    %*ENV<DATABASE_URL> = "sqlite:$dbfile";
    DB.set-shared(Nil);
    DB.shared.exec('CREATE TABLE registry_widgets (id INTEGER PRIMARY KEY, name TEXT)');
    DB.shared.exec('CREATE TABLE registry_gadgets (id INTEGER PRIMARY KEY, name TEXT, registry_widget_id INTEGER)');
    $name = DB.shared.name;
  }

  after-all {
    DB.shared.pool.disconnect-all;
    DB.set-shared($saved-shared);
    $saved-url.defined ?? (%*ENV<DATABASE_URL> = $saved-url) !! (%*ENV<DATABASE_URL>:delete);
    $dbfile.IO.unlink if $dbfile && $dbfile.IO.e;
  }

  before-each { RegistryWidget.destroy-all; RegistryGadget.destroy-all }

  it 'checks out, caches, and tracks a pooled connection, then releases it', {
    my $registry = ORM::ActiveRecord::Connection::Registry.new;
    my $db       = $registry.db-for($name);

    aggregate-failures {
      expect($db ~~ DB).to.be-truthy;
      expect(DB.shared.pool.stats<in-use>).to.eq(1);
      expect($registry.db-for($name) === $db).to.be-truthy;
      expect($registry.checked-out-names).to.eq(($name,));
    }

    $registry.release-all;
    expect(DB.shared.pool.stats<in-use>).to.eq(0);
  }

  it 'uses the shared connection when no registry is bound', {
    expect(RegistryWidget.db === DB.shared).to.be-truthy;
  }

  it 'routes a model through the registry when one is bound', {
    my $registry = ORM::ActiveRecord::Connection::Registry.new;
    {
      my $*AR-CONNECTION-REGISTRY = $registry;
      expect(RegistryWidget.db === $registry.db-for(RegistryWidget.connection-name)).to.be-truthy;
    }
    $registry.release-all;
  }

  it 'routes a relation query through the registry when one is bound', {
    my $registry = ORM::ActiveRecord::Connection::Registry.new;
    {
      my $*AR-CONNECTION-REGISTRY = $registry;
      RegistryWidget.all.all;
      expect($registry.checked-out-names).to.eq(($name,));
    }
    $registry.release-all;
  }

  it 'makes a registry write visible on the shared connection after release', {
    my $registry = ORM::ActiveRecord::Connection::Registry.new;
    {
      my $*AR-CONNECTION-REGISTRY = $registry;
      RegistryWidget.create({ name => 'from-registry' });
    }
    $registry.release-all;

    expect(DB.shared.exec('SELECT count(*) FROM registry_widgets')[0][0]).to.eq(1);
  }

  it 'routes an association collection query through the registry when one is bound', {
    my $widget = RegistryWidget.create({ name => 'owner' });
    RegistryGadget.create({ name => 'g', registry_widget_id => $widget.id });

    my $registry = ORM::ActiveRecord::Connection::Registry.new;
    {
      my $*AR-CONNECTION-REGISTRY = $registry;
      $widget.gadgets.list;
      expect($registry.checked-out-names).to.eq(($name,));
    }
    $registry.release-all;
  }

  context 'DB.current, the shared resolution point for every query path', {
    it 'is the shared connection when nothing is bound', {
      expect(DB.current === DB.shared).to.be-truthy;
    }

    it 'returns the async override when one is bound', {
      my $override = DB.shared;
      my $*AR-DB-OVERRIDE = $override;
      expect(DB.current === $override).to.be-truthy;
    }

    it 'routes through the registry when one is bound', {
      my $registry = ORM::ActiveRecord::Connection::Registry.new;
      {
        my $*AR-CONNECTION-REGISTRY = $registry;
        expect(DB.current === $registry.db-for($name)).to.be-truthy;
      }
      $registry.release-all;
    }

    it 'runs raw DB.current.exec on the registry connection, not the shared one', {
      my $registry = ORM::ActiveRecord::Connection::Registry.new;
      {
        my $*AR-CONNECTION-REGISTRY = $registry;
        DB.current.exec('SELECT count(*) FROM registry_widgets');
        expect(DB.shared.pool.stats<in-use>).to.eq(1);
      }
      $registry.release-all;

      expect(DB.shared.pool.stats<in-use>).to.eq(0);
    }
  }
}
