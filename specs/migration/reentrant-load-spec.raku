use lib 'lib';
use BDD::Behave;

%*ENV<DISABLE-SQL-LOG> = True;

my $has-sqlite = try {
  use DBIish;
  my $h = DBIish.connect('SQLite', :database(':memory:'));
  $h.dispose;
  True;
} // False;

use ORM::ActiveRecord::Adapter::Sqlite;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migrate;

sub migrate-fresh-db(--> List) {
  my $db = DB.new(adapter => SqliteAdapter.new(database => ':memory:'));
  DB.set-shared($db);

  Migrate.new(:args([])).run;

  $db.get-table-names.list.grep({ $_ ne 'migrations' }).sort.List;
}

my &group = $has-sqlite ?? &describe !! &xdescribe;

my $prior-shared;
my @first;
my @second;

group 'migrate re-entrancy within one process', {
  if !$has-sqlite { pending 'no sqlite driver available'; }

  before-all {
    if $has-sqlite {
      $prior-shared = DB.shared;

      @first  = migrate-fresh-db();
      @second = migrate-fresh-db();
    }
  }

  after-all {
    DB.set-shared($prior-shared) if $prior-shared.defined;
    $prior-shared = Nil;
  }

  it 'creates tables on the first migrate pass', {
    expect(@first.elems > 0).to.be-truthy;
  }

  it 'creates the same tables on a second pass in the same process', {
    expect(@second.join(',')).to.eq(@first.join(','));
  }
}
