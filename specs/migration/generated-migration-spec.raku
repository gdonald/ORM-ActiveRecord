use lib 'lib';
use lib 'specs/lib';
use MONKEY-SEE-NO-EVAL;
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Generator;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub column-names($name) {
  $adapter.get-fields(table => $name).map({ $_[0] }).list;
}

# EVAL once: re-evaluating the class declaration would redeclare it in GLOBAL.
my $widget-migration = EVAL Generator.new.render-create-migration(
  'CreateGenWidgets', '_gen_widgets', ['name:string', 'qty:integer']
);

describe 'running a generated create migration', {
  before-each {
    try { $adapter.ddl-drop-table('_gen_widgets') if table-exists('_gen_widgets') }
  }

  after-each {
    try { $adapter.ddl-drop-table('_gen_widgets') if table-exists('_gen_widgets') }
  }

  let(:migration, { $widget-migration });

  it 'creates the table when run up', {
    migration.new.up;
    expect(table-exists('_gen_widgets')).to.be-truthy;
  }

  it 'creates the declared columns', {
    migration.new.up;

    aggregate-failures {
      expect(column-names('_gen_widgets').grep({ $_ eq 'name' }).elems).to.be-truthy;
      expect(column-names('_gen_widgets').grep({ $_ eq 'qty' }).elems).to.be-truthy;
    }
  }

  it 'drops the table when run down', {
    migration.new.up;
    migration.new.down;
    expect(table-exists('_gen_widgets')).to.be-falsy;
  }
}
