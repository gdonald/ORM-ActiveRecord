use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Schema::Dumper;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub cleanup-tables {
  for < _dfk_books _dfk_authors > -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class DfkCreateAuthors is Migration {
  method change { self.create-table: '_dfk_authors', [ name => { :string, limit => 32 } ]; }
}

class DfkCreateBooks is Migration {
  method change {
    self.create-table: '_dfk_books', [
      title     => { :string, limit => 32 },
      author_id => { :integer, references => '_dfk_authors', on-delete => 'cascade' },
    ];
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

my $alter-capable = $has-db && $adapter.ref-supports-alter-foreign-key;
my &alter-it  = $alter-capable          ?? &it !! &xit;
my &inline-it = ($has-db && !$alter-capable) ?? &it !! &xit;

group 'dumping foreign keys', :order<defined>, {
  before-all {
    if $has-db {
      cleanup-tables;
      DfkCreateAuthors.new.up;
      DfkCreateBooks.new.up;
    }
  }
  after-all { if $has-db { cleanup-tables } }

  let(:schema, { SchemaDumper.new(adapter => $adapter).render-schema });

  alter-it 'emits an add-foreign-key statement for the reference (PostgreSQL/MySQL)', {
    expect(schema.contains("self.add-foreign-key: '_dfk_books', '_dfk_authors'")).to.be-truthy;
  }

  alter-it 'emits a remove-foreign-key statement for the reference (PostgreSQL/MySQL)', {
    expect(schema.contains("self.remove-foreign-key: '_dfk_books', to-table => '_dfk_authors'")).to.be-truthy;
  }

  alter-it 'removes foreign keys before dropping tables (PostgreSQL/MySQL)', {
    expect(schema.index("self.remove-foreign-key: '_dfk_books'")
             < schema.index("self.drop-table: '_dfk_authors'")).to.be-truthy;
  }

  inline-it 'emits an inline references adverb on the column (SQLite)', {
    expect(schema.contains("references => '_dfk_authors'")).to.be-truthy;
  }

  inline-it 'emits no remove-foreign-key for inline references (SQLite)', {
    expect(schema.contains('self.remove-foreign-key:')).to.be-falsy;
  }

  it 'records the on-delete action', {
    expect(schema.contains("on-delete => 'cascade'")).to.be-truthy;
  }
}
