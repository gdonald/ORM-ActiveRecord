use MONKEY-SEE-NO-EVAL;
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Schema::Dumper;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter   = DB.shared.adapter;
my $has-db    = $adapter.defined && $adapter.is-connected;
my $is-sqlite = $has-db && live-adapter-name($adapter) eq 'sqlite';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub cleanup-tables {
  for < _cc_people _cc_scores > -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

sub insert-person(Str:D $fname) {
  $adapter.exec('INSERT INTO _cc_people (fname, lname) VALUES (' ~ $adapter.bind-placeholder(1) ~ ", 'Lovelace')", $fname);
}

sub create-table-block(Str:D $schema, Str:D $table --> Str) {
  ~($schema ~~ / "    self.create-table: '$table'" .*? '];' /);
}

sub reload-table(Str:D $block) {
  my $migration = EVAL "use ORM::ActiveRecord::Schema::Migration; class :: is Migration \{ method up \{ $block \} \}";
  $migration.new.up;
}

class CcCreatePeople is Migration {
  method change {
    self.create-table: '_cc_people', [
      fname => { :string, limit => 50, null => False, check => "fname <> ''" },
      lname => { :string, limit => 50, null => False, check => "lname <> ''" },
    ];
  }
}

class CcCreateScores is Migration {
  method change {
    self.create-table: '_cc_scores', [
      points => { :integer, check => 'points >= 0' },
    ];
    self.add-check-constraint: '_cc_scores', 'points <= 100', name => 'cc_scores_points_max';
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'a column declared with a check option', :order<defined>, {
  before-all {
    if $has-db {
      cleanup-tables;
      CcCreatePeople.new.up;
    }
  }
  after-all { if $has-db { cleanup-tables } }

  it 'refuses an insert of an empty string', {
    expect({ insert-person('') }).to.raise-error;
  }

  it 'accepts a non-empty value', {
    expect({ insert-person('Ada') }).not.to.raise-error;
  }

  context 'when the schema is dumped', :order<defined>, {
    let(:schema, { SchemaDumper.new(adapter => $adapter).render-schema });

    it 'writes the check option on the column', {
      expect(create-table-block(schema, '_cc_people').contains('check => ')).to.be-truthy;
    }

    context 'and the table is reloaded from the dump', :order<defined>, {
      before-all {
        if $has-db {
          my $block = create-table-block(SchemaDumper.new(adapter => $adapter).render-schema, '_cc_people');

          $adapter.ddl-drop-table('_cc_people');
          reload-table($block);
        }
      }

      it 'still refuses an insert of an empty string', {
        expect({ insert-person('') }).to.raise-error;
      }

      it 'still accepts a non-empty value', {
        expect({ insert-person('Grace') }).not.to.raise-error;
      }
    }
  }
}

my &table-check-group = ($has-db && !$is-sqlite) ?? &describe !! &xdescribe;

table-check-group 'a column with a check option and a second check added by add-check-constraint', :order<defined>, {
  before-all {
    if $has-db && !$is-sqlite {
      cleanup-tables;
      CcCreateScores.new.up;
    }
  }
  after-all { if $has-db && !$is-sqlite { cleanup-tables } }

  let(:schema, { SchemaDumper.new(adapter => $adapter).render-schema });

  it 'dumps both checks joined with AND', {
    expect(create-table-block(schema, '_cc_scores').contains(') AND (')).to.be-truthy;
  }
}
