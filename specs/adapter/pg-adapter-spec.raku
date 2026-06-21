use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::TestSkip;
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Pg;
use ORM::ActiveRecord::Schema::Field;

%*ENV<DISABLE-SQL-LOG> = True;

# Resolve the active primary connection the same way the ORM does: from
# config/application.json for the current environment, with DATABASE_URL as an
# override (and the per-worker database suffix already applied under behave
# --parallel). So the spec activates whether postgres is selected via config or
# via DATABASE_URL.
my %cfg = (try { DB.read-config(name => 'primary') }) // %();
my $is-pg = normalize-adapter-name((%cfg<adapter> // '').Str) eq 'pg';

my $host     = %cfg<host>     // 'localhost';
my $user     = %cfg<user>     // 'postgres';
my $password = %cfg<password> // '';
my $database = %cfg<name>     // 'ar_test';
my $schema   = %cfg<schema>   // 'public';

sub conn() {
  PgAdapter.new(:$schema, :$host, :$database, :$user, :$password);
}

my $can-connect = $is-pg && (try {
  my $probe = conn();
  $probe.disconnect;
  True;
} // False);

describe 'PgAdapter direct integration', {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;

    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'connects from BUILD', {
      expect($pg.is-connected).to.be-truthy;
    }

    it 'reports the configured schema', {
      expect($pg.schema).to.eq('public');
    }

    it 'numbers the first bind placeholder as $1', {
      expect($pg.bind-placeholder(1)).to.eq('$1');
    }

    it 'numbers a later bind placeholder as $7', {
      expect($pg.bind-placeholder(7)).to.eq('$7');
    }

    it 'advertises advisory-lock support', {
      expect($pg.supports-advisory-locks).to.be-truthy;
    }

    it 'returns truthy from disconnect when a handle existed', {
      expect($pg.disconnect).to.be-truthy;
    }

    it 'reports not connected after disconnect', {
      $pg.disconnect;
      expect($pg.is-connected).to.be-falsy;
    }

    it 're-establishes the connection on reconnect', {
      $pg.disconnect;
      $pg.reconnect;
      expect($pg.is-connected).to.be-truthy;
    }
  }
}

describe 'PgAdapter coerce-read', {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'passes an undefined value through untouched', {
      expect($pg.coerce-read(Str, type => 'boolean')).to.be(Str);
    }

    it 'passes a value through when no type is given', {
      expect($pg.coerce-read('raw')).to.eq('raw');
    }

    it 'returns an existing Bool as-is', {
      expect($pg.coerce-read(True, type => 'boolean')).to.be(True);
    }

    it "reads 't' as True", {
      expect($pg.coerce-read('t', type => 'boolean')).to.be(True);
    }

    it "reads 'f' as False", {
      expect($pg.coerce-read('f', type => 'boolean')).to.eq(False);
    }

    it 'reads a timestamp string as a DateTime', {
      expect($pg.coerce-read('2026-05-09 12:34:56', type => 'timestamp')).to.be-a(DateTime);
    }

    it 'leaves an existing DateTime untouched for a date type', {
      my $dt = DateTime.new('2026-05-09T12:34:56Z');
      expect($pg.coerce-read($dt, type => 'timestamp')).to.be($dt);
    }

    it 'reads an integer column value as an Int', {
      expect($pg.coerce-read('42', type => 'integer')).to.eq(42);
    }

    it 'reads a numeric column value as a number', {
      expect($pg.coerce-read('3.5', type => 'numeric')).to.eq(3.5);
    }

    it 'falls through unknown types unchanged', {
      expect($pg.coerce-read('keepme', type => 'jsonb')).to.eq('keepme');
    }
  }
}

describe 'PgAdapter coerce-write', {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'passes an undefined value through untouched', {
      expect($pg.coerce-write(Int, type => 'boolean')).to.be(Int);
    }

    it "writes 'yes' as True", {
      expect($pg.coerce-write('yes', type => 'boolean')).to.be(True);
    }

    it "writes 'no' as False", {
      expect($pg.coerce-write('no', type => 'boolean')).to.eq(False);
    }

    it 'writes a timestamp string as a DateTime', {
      expect($pg.coerce-write('2026-05-09 12:34:56', type => 'datetime')).to.be-a(DateTime);
    }

    it 'falls through types it does not special-case', {
      expect($pg.coerce-write('verbatim', type => 'text')).to.eq('verbatim');
    }
  }
}

describe 'PgAdapter ddl column emission', {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'emits a string column with a length modifier', {
      expect($pg.ddl-column-defs('name' => { :string, limit => 10 })[0]).to.eq('name VARCHAR(10)');
    }

    it 'emits a text column', {
      expect($pg.ddl-column-defs('body' => { :text })[0]).to.eq('body TEXT');
    }

    it 'emits an integer column', {
      expect($pg.ddl-column-defs('qty' => { :integer })[0]).to.eq('qty INTEGER');
    }

    it 'emits a boolean column as BOOL', {
      expect($pg.ddl-column-defs('flag' => { :boolean })[0]).to.eq('flag BOOL');
    }

    it 'emits a decimal column with precision and scale', {
      expect($pg.ddl-column-defs('amount' => { :decimal, precision => 8, scale => 2 })[0]).to.eq('amount NUMERIC(8, 2)');
    }

    it 'emits a float column as DOUBLE PRECISION', {
      expect($pg.ddl-column-defs('ratio' => { :float })[0]).to.eq('ratio DOUBLE PRECISION');
    }

    it 'emits a datetime column as TIMESTAMPTZ', {
      expect($pg.ddl-column-defs('seen_at' => { :datetime })[0]).to.eq('seen_at TIMESTAMPTZ');
    }

    it 'emits a uuid column', {
      expect($pg.ddl-column-defs('token' => { :uuid })[0]).to.eq('token UUID');
    }

    it 'emits a binary column as BYTEA and ignores any limit', {
      expect($pg.ddl-column-defs('blob' => { :binary, limit => 99 })[0]).to.eq('blob BYTEA');
    }

    it 'emits a jsonb column', {
      expect($pg.ddl-column-defs('meta' => { :jsonb })[0]).to.eq('meta JSONB');
    }

    it 'emits an array column with a [] suffix', {
      expect($pg.ddl-column-defs('tags' => { :integer, :array })[0]).to.eq('tags INTEGER[]');
    }

    it 'appends a NOT NULL clause when null is false', {
      expect($pg.ddl-column-defs('req' => { :string, null => False })[0]).to.eq('req VARCHAR NOT NULL');
    }

    it 'appends a UNIQUE clause when unique is set', {
      expect($pg.ddl-column-defs('email' => { :string, unique => True })[0]).to.eq('email VARCHAR UNIQUE');
    }

    it 'emits a default literal for a string default', {
      expect($pg.ddl-column-defs('status' => { :string, default => 'new' })[0]).to.eq("status VARCHAR DEFAULT 'new'");
    }

    it 'emits a stored generated column', {
      expect($pg.ddl-column-defs('doubled' => { :integer, as => 'qty * 2', stored => True })[0])
        .to.eq('doubled INTEGER GENERATED ALWAYS AS (qty * 2) STORED');
    }

    it 'turns a reference into an INTEGER foreign-key column', {
      expect($pg.ddl-column-defs('author' => { :reference })[0]).to.eq('author_id INTEGER');
    }

    it 'expands a polymorphic reference into id and type columns', {
      my @defs = $pg.ddl-column-defs('owner' => { :reference, :polymorphic });
      expect(@defs.join(' | ')).to.eq('owner_id INTEGER | owner_type VARCHAR(255)');
    }

    it 'rejects an unknown column attribute', {
      expect({ $pg.ddl-column-defs('x' => { :nonsense }) }).to.raise-error;
    }

    it 'rejects charset and points at collation', {
      expect({ $pg.ddl-column-defs('x' => { :string, charset => 'utf8' }) }).to.raise-error;
    }
  }
}

describe 'PgAdapter create-table, introspection and crud', :order<defined>, {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    my $id1;
    my $id2;
    my @field-objs;

    before-each {
      $pg = conn();
      $pg.exec('DROP TABLE IF EXISTS pg_widgets CASCADE');
      $pg.ddl-create-table('pg_widgets', [
        name   => { :string, limit => 64 },
        qty    => { :integer, default => 0 },
        active => { :boolean, default => True },
        body   => { :text },
      ], comment => 'widget store');
      $pg.ddl-add-timestamps('pg_widgets');

      my %types = name => 'character varying', qty => 'integer',
                  active => 'boolean', body => 'text';

      my $s1 = $pg.build-insert(
        table => 'pg_widgets',
        attrs => { name => 'alpha', qty => 3, active => True, body => 'lorem' },
        :%types,
      );
      $id1 = $pg.exec-stmt($s1)[0][0].Int;

      my $s2 = $pg.build-insert(
        table => 'pg_widgets',
        attrs => { name => 'beta', qty => 7, active => False, body => 'ipsum' },
        :%types,
      );
      $id2 = $pg.exec-stmt($s2)[0][0].Int;

      @field-objs = $pg.get-fields(table => 'pg_widgets').map({
        Field.new(name => $_[0], type => $_[1]);
      });
    }

    after-each {
      $pg.exec('DROP TABLE IF EXISTS pg_widgets CASCADE') if $pg && $pg.is-connected;
      $pg.disconnect if $pg && $pg.is-connected;
    }

    it 'lists the new table via get-table-names', {
      expect(('pg_widgets' (elem) $pg.get-table-names.list).so).to.be-truthy;
    }

    it 'sees the id column via column-details', {
      expect($pg.column-details(table => 'pg_widgets').grep(*<name> eq 'id').elems).to.eq(1);
    }

    it 'reports a string column type from column-details', {
      my $col = $pg.column-details(table => 'pg_widgets').first(*<name> eq 'name');
      expect($col<type>).to.eq('character varying');
    }

    it 'reports nullability from column-details', {
      my $col = $pg.column-details(table => 'pg_widgets').first(*<name> eq 'body');
      expect($col<null>).to.be-truthy;
    }

    it 'reports a column default from column-details', {
      my $col = $pg.column-details(table => 'pg_widgets').first(*<name> eq 'qty');
      expect($col<default>.defined).to.be-truthy;
    }

    it 'returns RETURNING id as a positive integer on insert', {
      expect($id1).to.be-greater-than(0);
    }

    it 'assigns distinct ids to successive inserts', {
      expect($id2).to.be-greater-than($id1);
    }

    it 'round-trips a boolean true value', {
      my $row = $pg.get-record(table => 'pg_widgets', fields => @field-objs, where => { id => $id1 });
      expect($row<active>).to.eq(True);
    }

    it 'round-trips a boolean false value', {
      my $row = $pg.get-record(table => 'pg_widgets', fields => @field-objs, where => { id => $id2 });
      expect($row<active>).to.eq(False);
    }

    it 'round-trips an integer value', {
      my $row = $pg.get-record(table => 'pg_widgets', fields => @field-objs, where => { id => $id1 });
      expect($row<qty>).to.eq(3);
    }

    it 'coerces a TIMESTAMPTZ default to a DateTime', {
      my $row = $pg.get-record(table => 'pg_widgets', fields => @field-objs, where => { id => $id1 });
      expect($row<created_at>).to.be-a(DateTime);
    }

    it 'reports the affected row count from update-records', {
      expect($pg.update-records(table => 'pg_widgets', attrs => { qty => 99 }, types => { qty => 'integer' }, where => { id => $id1 })).to.eq(1);
    }

    it 'reports the affected row count from update-counter-records', {
      expect($pg.update-counter-records(table => 'pg_widgets', counters => { qty => 5 }, where => { id => $id1 })).to.eq(1);
    }

    it 'reports the deleted row count from delete-records', {
      expect($pg.delete-records(table => 'pg_widgets', where => { id => $id1 })).to.eq(1);
    }

    it 'returns ids from a batched insert-records', {
      my @ids = $pg.insert-records(
        table => 'pg_widgets',
        rows  => [ { name => 'g1', qty => 1 }, { name => 'g2', qty => 2 } ],
      );
      expect(@ids.elems).to.eq(2);
    }

    it 'counts upserted rows from upsert-records', {
      my @rows;
      @rows.push: %( id => $id1, name => 'alpha2', qty => 11 );
      my $n = $pg.upsert-records(table => 'pg_widgets', rows => @rows, unique-by => ['id']);
      expect($n).to.eq(1);
    }

    it 'lists declared sequences via get-sequences', {
      expect($pg.get-sequences.grep(*.contains('pg_widgets')).elems).to.be-greater-than(0);
    }

    it 'reports the primary-key constraint via get-constraints', {
      my @pks = $pg.get-constraints(table => 'pg_widgets').grep(*<type> eq 'primary-key');
      expect(@pks.elems).to.eq(1);
    }

    it 'reports an index via get-indexes after one is added', {
      $pg.exec('CREATE INDEX idx_pg_widgets_name ON pg_widgets (name)');
      expect($pg.get-indexes(table => 'pg_widgets').grep(*<name> eq 'idx_pg_widgets_name').elems).to.eq(1);
    }
  }
}

describe 'PgAdapter ddl alterations', :order<defined>, {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;

    before-each {
      $pg = conn();
      $pg.exec('DROP TABLE IF EXISTS pg_alter CASCADE');
      $pg.ddl-create-table('pg_alter', [ name => { :string, limit => 32 } ]);
    }

    after-each {
      $pg.exec('DROP TABLE IF EXISTS pg_alter CASCADE') if $pg && $pg.is-connected;
      $pg.disconnect if $pg && $pg.is-connected;
    }

    it 'adds a column', {
      $pg.ddl-add-column('pg_alter', 'qty' =>{ :integer });
      expect($pg.column-details(table => 'pg_alter').grep(*<name> eq 'qty').elems).to.eq(1);
    }

    it 'changes a column type', {
      $pg.ddl-add-column('pg_alter', 'qty' =>{ :string, limit => 8 });
      $pg.ddl-change-column('pg_alter', 'qty', 'integer', using => 'qty::integer');
      my $col = $pg.column-details(table => 'pg_alter').first(*<name> eq 'qty');
      expect($col<type>).to.eq('integer');
    }

    it 'sets a column default', {
      $pg.ddl-add-column('pg_alter', 'qty' =>{ :integer });
      $pg.ddl-change-column-default('pg_alter', 'qty', 7);
      my $col = $pg.column-details(table => 'pg_alter').first(*<name> eq 'qty');
      expect($col<default>.contains('7')).to.be-truthy;
    }

    it 'drops a column default', {
      $pg.ddl-add-column('pg_alter', 'qty' =>{ :integer, default => 7 });
      $pg.ddl-change-column-default('pg_alter', 'qty', Int);
      my $col = $pg.column-details(table => 'pg_alter').first(*<name> eq 'qty');
      expect($col<default>.defined).to.be-falsy;
    }

    it 'sets a column NOT NULL', {
      $pg.ddl-change-column-null('pg_alter', 'name', False);
      my $col = $pg.column-details(table => 'pg_alter').first(*<name> eq 'name');
      expect($col<null>).to.be-falsy;
    }

    it 'drops a column NOT NULL', {
      $pg.ddl-change-column-null('pg_alter', 'name', False);
      $pg.ddl-change-column-null('pg_alter', 'name', True);
      my $col = $pg.column-details(table => 'pg_alter').first(*<name> eq 'name');
      expect($col<null>).to.be-truthy;
    }

    it 'sets a column comment', {
      $pg.ddl-change-column-comment('pg_alter', 'name', 'the label');
      my $rows = $pg.exec(q:to/SQL/);
        SELECT d.description
          FROM pg_description d
          JOIN pg_attribute a ON a.attrelid = d.objoid AND a.attnum = d.objsubid
         WHERE d.objoid = 'pg_alter'::regclass AND a.attname = 'name'
        SQL
      expect($rows[0][0].Str).to.eq('the label');
    }

    it 'sets a table comment', {
      $pg.ddl-change-table-comment('pg_alter', 'a table');
      my $rows = $pg.exec(q{SELECT obj_description('pg_alter'::regclass)});
      expect($rows[0][0].Str).to.eq('a table');
    }
  }
}

describe 'PgAdapter json operators', {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'returns the column unchanged for an empty extract path', {
      expect($pg.json-extract-text-sql('data', [])).to.eq('data');
    }

    it 'chains -> hops with a final ->> for text extraction', {
      expect($pg.json-extract-text-sql('data', ['a', 'b', 'c'])).to.eq(q{data -> 'a' -> 'b' ->> 'c'});
    }

    it 'builds a jsonb containment predicate', {
      my $stmt = SqlStmt.new(:adapter($pg));
      expect($pg.json-contains-sql($stmt, 'data', { a => 1 }).contains('@>')).to.be-truthy;
    }

    it 'builds a jsonb key-existence predicate using jsonb_exists', {
      my $stmt = SqlStmt.new(:adapter($pg));
      expect($pg.json-has-key-sql($stmt, 'data', 'a').contains('jsonb_exists')).to.be-truthy;
    }
  }
}

describe 'PgAdapter advisory locks', :order<defined>, {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  {
      $pg.exec('SELECT pg_advisory_unlock_all()') if $pg && $pg.is-connected;
      $pg.disconnect if $pg && $pg.is-connected;
    }

    it 'acquires a blocking advisory lock', {
      expect($pg.get-advisory-lock('ar-pg-lock')).to.be-truthy;
    }

    it 'acquires a lock within a timeout when it is free', {
      expect($pg.get-advisory-lock('ar-pg-free', timeout => 0.5)).to.be-truthy;
    }

    it 'releases a held advisory lock', {
      $pg.get-advisory-lock('ar-pg-rel');
      expect($pg.release-advisory-lock('ar-pg-rel')).to.be-truthy;
    }

    it 'fails to acquire within the timeout when another connection holds it', {
      my $other = conn();
      LEAVE { $other.exec('SELECT pg_advisory_unlock_all()'); $other.disconnect; }
      $other.get-advisory-lock('ar-pg-contended');
      expect($pg.get-advisory-lock('ar-pg-contended', timeout => 0.3)).to.be-falsy;
    }
  }
}

describe 'PgAdapter extensions, enums and constraints', :order<defined>, {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    it 'enables and disables an extension', {
      $pg.ddl-enable-extension('pgcrypto');
      $pg.ddl-disable-extension('pgcrypto');
      my $rows = $pg.exec(q{SELECT count(*) FROM pg_extension WHERE extname = 'pgcrypto'});
      expect($rows[0][0].Int).to.eq(0);
    }

    it 'creates an enum type', {
      $pg.ddl-drop-enum('pg_mood', :if-exists);
      $pg.ddl-create-enum('pg_mood', ['sad', 'ok', 'happy']);
      LEAVE { $pg.ddl-drop-enum('pg_mood', :if-exists); }
      my $rows = $pg.exec(q{SELECT count(*) FROM pg_type WHERE typname = 'pg_mood'});
      expect($rows[0][0].Int).to.eq(1);
    }

    it 'rejects creating an enum with no values', {
      expect({ $pg.ddl-create-enum('pg_empty', []) }).to.raise-error;
    }

    it 'adds a value to an existing enum', {
      $pg.ddl-drop-enum('pg_mood2', :if-exists);
      $pg.ddl-create-enum('pg_mood2', ['sad', 'happy']);
      LEAVE { $pg.ddl-drop-enum('pg_mood2', :if-exists); }
      $pg.ddl-add-enum-value('pg_mood2', 'meh', after => 'sad');
      my $rows = $pg.exec(q{SELECT count(*) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'pg_mood2' AND e.enumlabel = 'meh'});
      expect($rows[0][0].Int).to.eq(1);
    }

    it 'rejects an enum value with both before and after', {
      expect({ $pg.ddl-add-enum-value('pg_x', 'v', before => 'a', after => 'b') }).to.raise-error;
    }

    it 'renames an enum value', {
      $pg.ddl-drop-enum('pg_mood3', :if-exists);
      $pg.ddl-create-enum('pg_mood3', ['old']);
      LEAVE { $pg.ddl-drop-enum('pg_mood3', :if-exists); }
      $pg.ddl-rename-enum-value('pg_mood3', 'old', 'new');
      my $rows = $pg.exec(q{SELECT count(*) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'pg_mood3' AND e.enumlabel = 'new'});
      expect($rows[0][0].Int).to.eq(1);
    }

    it 'adds and removes an exclusion constraint', {
      $pg.exec('DROP TABLE IF EXISTS pg_excl CASCADE');
      $pg.exec('CREATE TABLE pg_excl (room INT, during INT4RANGE)');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_excl CASCADE'); }
      $pg.ddl-add-exclusion-constraint('pg_excl', 'during WITH &&', name => 'excl_room');
      $pg.ddl-remove-exclusion-constraint('pg_excl', name => 'excl_room');
      my @con = $pg.get-constraints(table => 'pg_excl').grep(*<name> eq 'excl_room');
      expect(@con.elems).to.eq(0);
    }

    it 'requires a name to remove an exclusion constraint', {
      expect({ $pg.ddl-remove-exclusion-constraint('pg_excl') }).to.raise-error;
    }

    it 'validates a NOT VALID foreign key', {
      $pg.exec('DROP TABLE IF EXISTS pg_children CASCADE');
      $pg.exec('DROP TABLE IF EXISTS pg_parents CASCADE');
      $pg.exec('CREATE TABLE pg_parents (id SERIAL PRIMARY KEY)');
      $pg.exec('CREATE TABLE pg_children (id SERIAL PRIMARY KEY, parent_id INT)');
      LEAVE {
        $pg.exec('DROP TABLE IF EXISTS pg_children CASCADE');
        $pg.exec('DROP TABLE IF EXISTS pg_parents CASCADE');
      }
      $pg.exec('ALTER TABLE pg_children ADD CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES pg_parents(id) NOT VALID');
      $pg.ddl-validate-foreign-key('pg_children', 'fk_parent');
      my $rows = $pg.exec(q{SELECT convalidated FROM pg_constraint WHERE conname = 'fk_parent'});
      expect($rows[0][0].so).to.be-truthy;
    }
  }
}

describe 'PgAdapter id-column and type mapping', :order<defined>, {
  if !$is-pg {
    pending 'pg-only';
  } elsif !$can-connect {
    pending "No reachable PostgreSQL at $host";
  } else {
    my $pg;
    before-each { $pg = conn(); }
    after-each  { $pg.disconnect if $pg && $pg.is-connected; }

    sub id-type-of(Str:D $table --> Str) {
      $pg.column-details(table => $table).first(*<name> eq 'id')<type>;
    }

    it 'emits a BIGSERIAL id for a bigint primary key', {
      $pg.exec('DROP TABLE IF EXISTS pg_id_big CASCADE');
      $pg.ddl-create-table('pg_id_big', [ name => { :string } ], id => 'bigint');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_id_big CASCADE'); }
      expect(id-type-of('pg_id_big')).to.eq('bigint');
    }

    it 'emits a UUID id for a uuid primary key', {
      $pg.exec('DROP TABLE IF EXISTS pg_id_uuid CASCADE');
      $pg.ddl-create-table('pg_id_uuid', [ name => { :string } ], id => 'uuid');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_id_uuid CASCADE'); }
      expect(id-type-of('pg_id_uuid')).to.eq('uuid');
    }

    it 'emits a VARCHAR id for a string primary key', {
      $pg.exec('DROP TABLE IF EXISTS pg_id_str CASCADE');
      $pg.ddl-create-table('pg_id_str', [ name => { :string } ], id => 'string');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_id_str CASCADE'); }
      expect(id-type-of('pg_id_str')).to.eq('character varying');
    }

    it 'routes an unusual id type through sql-type-for', {
      $pg.exec('DROP TABLE IF EXISTS pg_id_small CASCADE');
      $pg.ddl-create-table('pg_id_small', [ name => { :string } ], id => 'smallint');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_id_small CASCADE'); }
      expect(id-type-of('pg_id_small')).to.eq('smallint');
    }

    it 'emits a foreign-key constraint for a reference column at create time', {
      $pg.exec('DROP TABLE IF EXISTS pg_fksrc CASCADE');
      $pg.exec('DROP TABLE IF EXISTS pgrefs CASCADE');
      $pg.ddl-create-table('pgrefs', [ name => { :string } ]);
      $pg.ddl-create-table('pg_fksrc', [ title => { :string }, pgref => { :reference } ]);
      LEAVE {
        $pg.exec('DROP TABLE IF EXISTS pg_fksrc CASCADE');
        $pg.exec('DROP TABLE IF EXISTS pgrefs CASCADE');
      }
      my @fks = $pg.get-constraints(table => 'pg_fksrc').grep(*<type> eq 'foreign-key');
      expect(@fks.elems).to.eq(1);
    }

    it 'adds a column only when it does not already exist', {
      $pg.exec('DROP TABLE IF EXISTS pg_ine CASCADE');
      $pg.exec('CREATE TABLE pg_ine (a INTEGER)');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_ine CASCADE'); }
      $pg.ddl-add-column('pg_ine', 'b' => { :integer }, :if-not-exists);
      $pg.ddl-add-column('pg_ine', 'b' => { :integer }, :if-not-exists);
      expect($pg.column-details(table => 'pg_ine').grep(*<name> eq 'b').elems).to.eq(1);
    }

    it 'quotes a collation on a column definition', {
      expect($pg.ddl-column-defs('name' => { :string, collation => 'en_US' })[0])
        .to.eq('name VARCHAR COLLATE "en_US"');
    }

    it 'backfills existing nulls when setting NOT NULL with a default', {
      $pg.exec('DROP TABLE IF EXISTS pg_backfill CASCADE');
      $pg.exec('CREATE TABLE pg_backfill (qty INTEGER)');
      $pg.exec('INSERT INTO pg_backfill (qty) VALUES (NULL)');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_backfill CASCADE'); }
      $pg.ddl-change-column-null('pg_backfill', 'qty', False, default => 0);
      expect($pg.exec('SELECT qty FROM pg_backfill')[0][0].Int).to.eq(0);
    }

    it 'validates a NOT VALID check constraint', {
      $pg.exec('DROP TABLE IF EXISTS pg_check CASCADE');
      $pg.exec('CREATE TABLE pg_check (qty INTEGER)');
      $pg.exec('ALTER TABLE pg_check ADD CONSTRAINT chk_qty CHECK (qty >= 0) NOT VALID');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_check CASCADE'); }
      $pg.ddl-validate-check-constraint('pg_check', 'chk_qty');
      my $rows = $pg.exec(q{SELECT convalidated FROM pg_constraint WHERE conname = 'chk_qty'});
      expect($rows[0][0].so).to.be-truthy;
    }

    # Every branch of sql-type-for, exercised through ALTER COLUMN TYPE. The
    # table has no rows, so the USING cast only needs to be a valid expression.
    it 'maps every alterable column type through sql-type-for', {
      my @cases =
        ('bigint',   'bigint',            'bigint'),
        ('smallint', 'smallint',          'smallint'),
        ('boolean',  'boolean',           'boolean'),
        ('decimal',  'numeric',           'numeric'),
        ('float',    'double precision',  'double precision'),
        ('money',    'money',             'money'),
        ('datetime', 'timestamptz',       'timestamp with time zone'),
        ('date',     'date',              'date'),
        ('time',     'time',              'time without time zone'),
        ('interval', 'interval',          'interval'),
        ('uuid',     'uuid',              'uuid'),
        ('binary',   'bytea',             'bytea'),
        ('jsonb',    'jsonb',             'jsonb');

      $pg.exec('DROP TABLE IF EXISTS pg_sqltypes CASCADE');
      $pg.exec('CREATE TABLE pg_sqltypes (id SERIAL PRIMARY KEY)');
      LEAVE { $pg.exec('DROP TABLE IF EXISTS pg_sqltypes CASCADE'); }

      aggregate-failures {
        for @cases -> ($logical, $cast, $expected) {
          my $col = 'c_' ~ $logical;
          $pg.exec("ALTER TABLE pg_sqltypes ADD COLUMN $col TEXT");
          $pg.ddl-change-column('pg_sqltypes', $col, $logical, using => "$col\::$cast");
          my $got = $pg.column-details(table => 'pg_sqltypes').first(*<name> eq $col)<type>;
          expect($got).to.eq($expected);
        }
      }
    }
  }
}
