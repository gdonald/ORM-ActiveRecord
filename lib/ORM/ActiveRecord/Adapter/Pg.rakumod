
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

class PgAdapter is SqlAdapter is export {
  has Str $.schema;
  has Str $!host;
  has Str $!database;
  has Str $!user;
  has Str $!password;

  submethod BUILD(Str :$!schema, Str :$!host, Str :$!database, Str :$!user, Str :$!password) {
    self.connect;
  }

  submethod DESTROY {
    self.disconnect;
  }

  method connect() {
    return if self.db.defined;
    self.db = DBIish.connect('Pg', :$!schema, :$!host, :$!database, :$!user, :$!password);
    self.db.do('SET client_min_messages = WARNING');
  }

  method bind-placeholder(Int:D $n --> Str) {
    '$' ~ $n;
  }

  method coerce-read($value, Str :$type) {
    return $value without $value;
    return $value unless $type.defined;
    given $type {
      when /:i ^ bool/ {
        return $value if $value ~~ Bool;
        my $s = $value.Str.lc;
        return True  if $s eq 't' | 'true'  | '1' | 'y' | 'yes';
        return False if $s eq 'f' | 'false' | '0' | 'n' | 'no';
        $value.so;
      }
      when /:i timestamp | ^ date | ^ time / {
        return $value if $value ~~ DateTime;
        return $value if $value ~~ Date;
        my $s = $value.Str;
        return $value unless $s;
        my $iso = $s.subst(' ', 'T');
        return DateTime.new($iso) if $iso ~~ /^ \d ** 4 '-' \d\d '-' \d\d 'T' \d\d ':' \d\d ':' \d\d /;
        $value;
      }
      when /:i ^ (int | bigint | smallint | numeric | decimal | real | double) / {
        return $value if $value ~~ Numeric;
        my $s = $value.Str;
        return $value unless $s;
        $type ~~ /:i ^ (int | bigint | smallint) / ?? $s.Int !! $s.Numeric;
      }
      default { $value }
    }
  }

  method coerce-write($value, Str :$type) {
    return $value without $value.defined;
    return $value unless $type.defined;
    given $type {
      when /:i ^ bool/ {
        return $value if $value ~~ Bool;
        my $s = $value.Str.lc;
        return True  if $s eq 't' | 'true'  | '1' | 'y' | 'yes';
        return False if $s eq 'f' | 'false' | '0' | 'n' | 'no';
        $value.so;
      }
      when /:i timestamp | ^ date | ^ time / {
        return $value if $value ~~ DateTime | Date;
        my $s = $value.Str;
        return $value unless $s;
        my $iso = $s.subst(' ', 'T');
        return DateTime.new($iso) if $iso ~~ /^ \d ** 4 '-' \d\d '-' \d\d 'T' \d\d ':' \d\d ':' \d\d /;
        $value;
      }
      default { $value }
    }
  }

  method build-insert(Str:D :$table, :%attrs, :%types = {} --> SqlStmt) {
    my %fvs = self.without-excluded-fields(%attrs);
    my @keys = %fvs.keys.grep({ %fvs{$_}.defined });
    my $fields = @keys.join(', ');
    my @values = @keys.map({ %fvs{$_} });
    my @types  = @keys.map({ %types{$_} // Str });
    my $stmt = SqlStmt.new(:adapter(self));
    my $values = self.build-values-list($stmt, :@values, :@types);

    $stmt.sql = qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
      RETURNING id
      SQL

    $stmt;
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my %types = self!types-from-fields($obj);
    my $stmt = self.build-insert(:$table, :%attrs, :%types);

    self.exec-stmt($stmt)[0][0].Int;
  }

  method !types-from-fields(Mu:D $obj) {
    my %types;
    for $obj.fields -> $f { %types{$f.name} = $f.type }
    %types;
  }

  method get-fields(Str:D :$table) {
    my $type = 'character varying';
    my $names = <column_name data_type>;
    my @fields = $names.map({ Field.new(:name($_), :$type) });

    my $stmt = self.build-select(
      :@fields,
      table => 'information_schema.columns',
      where => { 'table_schema' => 'public', 'table_name' => $table },
      order => <ordinal_position>.list,
    );

    self.exec-stmt($stmt);
  }

  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    self.exec("DROP TABLE IF EXISTS {$_} CASCADE") for @tables;
    @tables;
  }

  method get-table-names {
    my @fields = <table_name>.map({ Field.new(:name($_), :type('character varying')) });
    my $stmt = self.build-select(
      :@fields,
      table => 'information_schema.tables',
      where => { 'table_schema' => 'public' },
      order => <table_name>.list,
    );

    self.exec-stmt($stmt).map({ $_[0] });
  }

  method delete-records(Str:D :$table, :%where, :%where-not) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $where-sql = self.build-where($stmt, %where, %where-not);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    $stmt.sql = qq:to/SQL/;
      WITH deleted AS (
        DELETE FROM $table
        $where-clause
        RETURNING *
      ) SELECT count(*)
        FROM deleted
      SQL

    self.exec-stmt($stmt)[0][0].Int;
  }

  method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
    my $stmt = self.build-update-where(:$table, :%attrs, :%types, :%where, :%where-not, :@or-groups, :@locking-bump);
    my $inner = $stmt.sql.chomp;
    $stmt.sql = qq:to/SQL/;
      WITH updated AS ( $inner RETURNING * )
      SELECT count(*) FROM updated
      SQL
    self.exec-stmt($stmt)[0][0].Int;
  }

  method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
    my $stmt = self.build-update-counters-where(:$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump);
    my $inner = $stmt.sql.chomp;
    $stmt.sql = qq:to/SQL/;
      WITH updated AS ( $inner RETURNING * )
      SELECT count(*) FROM updated
      SQL
    self.exec-stmt($stmt)[0][0].Int;
  }

  method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List) {
    my $stmt = self.build-insert-many(:$table, :@rows, :%types);
    $stmt.sql ~= ' ON CONFLICT DO NOTHING' if $skip-conflict;
    $stmt.sql ~= ' RETURNING id';
    self.exec-stmt($stmt).map({ .[0].Int }).list;
  }

  method upsert-records(Str:D :$table, :@rows, :%types = {}, :@unique-by = ('id',), :@update-cols = () --> Int) {
    my @conflict-cols = @unique-by.elems ?? @unique-by.list !! ('id',);
    my Bool $include-id = so 'id' eq any(@conflict-cols);
    my @cols = self.union-insert-keys(@rows, :$include-id);
    die 'upsert-all: no columns to upsert' unless @cols.elems;
    my @update = @update-cols.elems
      ?? @update-cols.list
      !! @cols.grep({ $_ ne any(@conflict-cols) });
    my $stmt = self.build-insert-many(:$table, :@rows, :%types, :keys(@cols), :$include-id);
    my $conflict-list = @conflict-cols.join(', ');
    if @update.elems {
      my $set-list = @update.map({ "$_ = EXCLUDED.$_" }).join(', ');
      $stmt.sql ~= " ON CONFLICT ($conflict-list) DO UPDATE SET $set-list";
    } else {
      $stmt.sql ~= " ON CONFLICT ($conflict-list) DO NOTHING";
    }
    my $inner = $stmt.sql.chomp;
    $stmt.sql = qq:to/SQL/;
      WITH upserted AS ( $inner RETURNING * )
      SELECT count(*) FROM upserted
      SQL
    self.exec-stmt($stmt)[0][0].Int;
  }


  # ---- DDL emission ----

  method ddl-create-table(Str:D $table, @params, :@foreign-keys is copy,
                          :$force, Bool :$temporary = False, Bool :$if-not-exists = False,
                          :$id = True, :$primary-key, :$comment) {
    self.ddl-force-drop($table, $force);

    # The primary key is a separate ALTER, so IF NOT EXISTS can't make the whole
    # operation atomic — skip entirely when the table is already present.
    return if $if-not-exists && self.get-table-names.list.grep(* eq $table).elems;

    my %pk = self.pk-plan(:$id, :$primary-key);
    my @comments;
    my @field-defs = self!build-fields(@params, :@foreign-keys, :@comments);
    my $prefix = self.ref-create-table-prefix(:$temporary, :$if-not-exists);

    my @cols;
    @cols.push(self!pg-id-column(%pk<pk-name>, %pk<id-type>)) if %pk<emit-id-col>;
    @cols.append(@field-defs);

    self.exec("{$prefix}$table ( {@cols.join(', ')} )");

    if %pk<want-pk> {
      self.exec("ALTER TABLE $table ADD CONSTRAINT {$table}_pkey PRIMARY KEY ({%pk<pk-cols>.join(', ')})");
    }

    for @foreign-keys -> $fk {
      self.exec(qq:to/SQL/);
        ALTER TABLE $table
        ADD CONSTRAINT fk_{$fk}_id
        FOREIGN KEY ({$fk}_id)
        REFERENCES {$fk ~ 's'}(id)
        SQL
    }

    # PostgreSQL has no inline column-comment syntax, so comments collected
    # during build-fields are emitted as separate COMMENT ON statements.
    self.ddl-change-column-comment($table, .key, .value) for @comments;
    self.ddl-change-table-comment($table, $comment) if $comment.defined;
  }

  method !pg-id-column(Str:D $name, Str:D $type --> Str) {
    given $type {
      when 'integer'              { "$name SERIAL" }
      when 'bigint' | 'bigserial' { "$name BIGSERIAL" }
      when 'uuid'                 { "$name UUID DEFAULT gen_random_uuid()" }
      when 'string' | 'text'      { "$name VARCHAR(255)" }
      default                     { "$name " ~ self!sql-type-for($type) }
    }
  }

  method ddl-add-column(Str:D $table, Pair:D $param, Bool :$if-not-exists = False) {
    my $clause = $if-not-exists ?? self.ref-column-if-not-exists-clause !! '';
    my @fk;
    my @comments;
    for self!build-fields([$param], foreign-keys => @fk, :@comments) -> $col {
      self.exec("ALTER TABLE $table ADD COLUMN {$clause}$col");
    }
    self.ddl-change-column-comment($table, .key, .value) for @comments;
  }

  method ddl-column-defs(Pair:D $param --> List) {
    my @fk;
    self!build-fields([$param], foreign-keys => @fk);
  }

  method ref-drop-cascade-suffix(--> Str) { ' CASCADE' }

  method ref-column-if-not-exists-clause(--> Str) { 'IF NOT EXISTS ' }
  method ref-column-if-exists-clause(--> Str)     { 'IF EXISTS ' }

  method ddl-change-column(Str:D $table, Str:D $name, Str:D $type, *%opts) {
    my $sql-type = self!sql-type-for($type, limit => %opts<limit>);
    my $using    = %opts<using> // '';
    my $using-clause = $using ?? " USING $using" !! '';

    self.exec("ALTER TABLE $table ALTER COLUMN $name TYPE $sql-type$using-clause");

    self.ddl-change-column-default($table, $name, %opts<default>)
      if %opts<default>:exists;

    self.ddl-change-column-null($table, $name, %opts<null>.so)
      if %opts<null>:exists;

    self.ddl-change-column-comment($table, $name, %opts<comment>)
      if %opts<comment>:exists;
  }

  method ddl-change-column-default(Str:D $table, Str:D $name, $value) {
    if $value.defined {
      my $literal = self!default-literal($value);
      self.exec("ALTER TABLE $table ALTER COLUMN $name SET DEFAULT $literal");
    } else {
      self.exec("ALTER TABLE $table ALTER COLUMN $name DROP DEFAULT");
    }
  }

  method ddl-change-column-null(Str:D $table, Str:D $name, Bool:D $null, :$default) {
    if !$null && $default.defined {
      my $literal = self!default-literal($default);
      self.exec("UPDATE $table SET $name = $literal WHERE $name IS NULL");
    }

    if $null {
      self.exec("ALTER TABLE $table ALTER COLUMN $name DROP NOT NULL");
    } else {
      self.exec("ALTER TABLE $table ALTER COLUMN $name SET NOT NULL");
    }
  }

  method ddl-change-column-comment(Str:D $table, Str:D $name, $comment) {
    if $comment.defined {
      my $literal = self!string-literal($comment.Str);
      self.exec("COMMENT ON COLUMN $table.$name IS $literal");
    } else {
      self.exec("COMMENT ON COLUMN $table.$name IS NULL");
    }
  }

  method ddl-change-table-comment(Str:D $table, $comment) {
    if $comment.defined {
      my $literal = self!string-literal($comment.Str);
      self.exec("COMMENT ON TABLE $table IS $literal");
    } else {
      self.exec("COMMENT ON TABLE $table IS NULL");
    }
  }

  method !sql-type-for(Str:D $type, :$limit) {
    given $type {
      when 'string'                 { 'VARCHAR' ~ ($limit ?? "($limit)" !! '') }
      when 'text'                   { 'TEXT' }
      when 'integer'                { 'INTEGER' }
      when 'bigint'                 { 'BIGINT' }
      when 'smallint'               { 'SMALLINT' }
      when 'boolean'                { 'BOOL' }
      when 'decimal' | 'numeric'    { 'NUMERIC' }
      when 'float'                  { 'DOUBLE PRECISION' }
      when 'money'                  { 'MONEY' }
      when 'datetime' | 'timestamp' | 'timestamptz' { 'TIMESTAMPTZ' }
      when 'date'                   { 'DATE' }
      when 'time'                   { 'TIME' }
      when 'interval'               { 'INTERVAL' }
      when 'uuid'                   { 'UUID' }
      when 'binary'                 { 'BYTEA' }
      default                       { $type.uc }
    }
  }

  method !default-literal($value --> Str) {
    return 'NULL' without $value;
    return $value().Str if $value ~~ Callable;
    return ($value ?? "'t'" !! "'f'") if $value ~~ Bool;
    return $value.Str if $value ~~ Numeric;
    self!string-literal($value.Str);
  }

  method !quote-collation(Str:D $name --> Str) {
    '"' ~ $name.subst('"', '""', :g) ~ '"';
  }

  # ---- JSON / JSONB operators (PostgreSQL) ----

  # Chain `-> 'a' -> 'b' ->> 'last'` so the final hop returns text.
  method json-extract-text-sql(Str:D $col, @path --> Str) {
    return $col unless @path.elems;
    my @p   = @path;
    my $last = @p.pop;
    my $expr = $col;
    $expr ~= " -> '$_'" for @p;
    $expr ~= " ->> '$last'";
    $expr;
  }

  method json-contains-sql(SqlStmt:D $stmt, Str:D $col, $data --> Str) {
    "$col @> " ~ $stmt.placeholder(self.json-literal($data)) ~ '::jsonb';
  }

  # The `?` jsonb operator collides with bind placeholders, so use the
  # equivalent function form.
  method json-has-key-sql(SqlStmt:D $stmt, Str:D $col, Str:D $key --> Str) {
    "jsonb_exists($col, " ~ $stmt.placeholder($key) ~ ')';
  }

  method !string-literal(Str:D $s --> Str) {
    "'" ~ $s.subst("'", "''", :g) ~ "'";
  }

  method ddl-add-timestamps(Str:D $table) {
    self.exec(qq:to/SQL/);
      ALTER TABLE $table
      ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      SQL
  }

  method ref-fk-not-valid-suffix(--> Str) { ' NOT VALID' }

  method ref-check-not-valid-suffix(--> Str) { ' NOT VALID' }

  method ddl-validate-foreign-key(Str:D $table, Str:D $name) {
    self.exec("ALTER TABLE $table VALIDATE CONSTRAINT $name");
  }

  method ddl-validate-check-constraint(Str:D $table, Str:D $name) {
    self.exec("ALTER TABLE $table VALIDATE CONSTRAINT $name");
  }

  method ddl-add-exclusion-constraint(Str:D $table, Str:D $expression,
                                      Str  :$using = 'gist',
                                      Str  :$name,
                                      Str  :$where,
                                      Bool :$deferrable = False,
                                      Bool :$initially-deferred = False) {
    my $cname  = $name // "excl_{$table}_" ~ self.ref-expr-hash($expression);
    my $where-clause = $where.defined && $where.chars ?? " WHERE ($where)" !! '';
    my $deferr = self.ref-unique-deferrable-suffix(:$deferrable, :$initially-deferred);

    self.exec("ALTER TABLE $table ADD CONSTRAINT $cname EXCLUDE USING $using ($expression)$where-clause$deferr");
  }

  method ddl-remove-exclusion-constraint(Str:D $table,
                                         Str :$name) {
    die 'remove-exclusion-constraint: :name is required' unless $name.defined;
    self.exec("ALTER TABLE $table DROP CONSTRAINT $name");
  }

  method ddl-enable-extension(Str:D $name) {
    self.exec(qq{CREATE EXTENSION IF NOT EXISTS "$name"});
  }

  method ddl-disable-extension(Str:D $name, Bool :$cascade = False) {
    my $suffix = $cascade ?? ' CASCADE' !! '';
    self.exec(qq{DROP EXTENSION IF EXISTS "$name"$suffix});
  }

  method ddl-create-enum(Str:D $name, @values) {
    die 'create-enum: at least one value is required' unless @values.elems;
    my $vals = @values.map({ self!string-literal($_.Str) }).join(', ');
    self.exec("CREATE TYPE $name AS ENUM ($vals)");
  }

  method ddl-drop-enum(Str:D $name, Bool :$if-exists = False) {
    my $clause = $if-exists ?? 'IF EXISTS ' !! '';
    self.exec("DROP TYPE {$clause}$name");
  }

  method ddl-add-enum-value(Str:D $name, Str:D $value,
                            Str :$before, Str :$after, Bool :$if-not-exists = False) {
    die 'add-enum-value: pass :before or :after, not both'
      if $before.defined && $after.defined;

    my $exists = $if-not-exists ?? 'IF NOT EXISTS ' !! '';
    my $pos = $before.defined ?? ' BEFORE ' ~ self!string-literal($before)
            !! $after.defined  ?? ' AFTER '  ~ self!string-literal($after)
            !! '';

    self.exec("ALTER TYPE $name ADD VALUE {$exists}{self!string-literal($value)}$pos");
  }

  method ddl-rename-enum-value(Str:D $name, Str:D $from, Str:D $to) {
    self.exec("ALTER TYPE $name RENAME VALUE {self!string-literal($from)} TO {self!string-literal($to)}");
  }

  method !build-fields(@params, :@foreign-keys, :@comments) {
    my @fields;

    for @params {
      my $name = $_.keys.first;
      my $field_name = $name ~~ Pair ?? $name.keys.first !! $name;

      my Bool $is-reference   = $_{$name}<reference>:exists;
      my Bool $is-polymorphic = ($_{$name}<polymorphic>:exists) && $_{$name}<polymorphic>.so;

      if $is-reference && $is-polymorphic {
        @fields.push($field_name ~ '_id INTEGER');
        @fields.push($field_name ~ '_type VARCHAR(255)');
        next;
      }

      my $type  = '';
      my $limit = '';
      my $null  = '';
      my Bool $has-default = False;
      my $default-value;
      my $collation;
      my $generated-as;
      my Bool $stored = False;
      my $comment;
      my Bool $is-decimal = False;
      my Bool $is-binary = False;
      my $precision;
      my $scale;

      for $_{$name}.keys -> $attr {
        my $value = $_{$name}{$attr};

        given $attr {
          when 'string'    { $type = 'VARCHAR' }
          when 'text'      { $type = 'TEXT' }
          when 'integer'   { $type = 'INTEGER' }
          when 'bigint'    { $type = 'BIGINT' }
          when 'smallint'  { $type = 'SMALLINT' }
          when 'boolean'   { $type = 'BOOL' }
          when 'decimal' | 'numeric' { $type = 'NUMERIC'; $is-decimal = True }
          when 'float'     { $type = 'DOUBLE PRECISION' }
          when 'money'     { $type = 'MONEY' }
          when 'datetime' | 'timestamp' { $type = 'TIMESTAMPTZ' }
          when 'timestamptz' { $type = 'TIMESTAMPTZ' }
          when 'date'      { $type = 'DATE' }
          when 'time'      { $type = 'TIME' }
          when 'interval'  { $type = 'INTERVAL' }
          when 'uuid'      { $type = 'UUID' }
          when 'binary'    { $type = 'BYTEA'; $is-binary = True }
          when 'json'      { $type = 'JSON' }
          when 'jsonb'     { $type = 'JSONB' }
          when 'hstore'    { $type = 'HSTORE' }
          when 'xml'       { $type = 'XML' }
          when 'limit'     { $limit = '(' ~ $value ~ ')' }
          when 'precision' { $precision = $value }
          when 'scale'     { $scale = $value }
          when 'default'   { $has-default = True; $default-value = $value }
          when 'null'      { $null = $value }
          when 'collation' { $collation = $value }
          when 'charset'   { die 'PgAdapter: charset is not supported (use collation)' }
          when 'as'        { $generated-as = $value }
          when 'stored'    { $stored = $value.so }
          when 'virtual'   { }
          when 'comment'   { $comment = $value }
          when 'reference' {
            @foreign-keys.push($field_name);
            $type = 'INTEGER';
            $field_name = $field_name ~ '_id';
          }
          default { die 'PgAdapter: unknown column attr: ' ~ $attr }
        }
      }

      if $is-decimal && $precision.defined {
        $limit = "($precision" ~ ($scale.defined ?? ", $scale" !! '') ~ ')';
      }

      # BYTEA takes no length modifier; a stray `limit` is ignored.
      $limit = '' if $is-binary;

      my $col = $field_name ~ ' ' ~ $type ~ $limit;

      $col ~= ' COLLATE ' ~ self!quote-collation($collation) if $collation.defined;

      if $generated-as.defined {
        # PostgreSQL only persists generated columns (no VIRTUAL before PG 18).
        $col ~= " GENERATED ALWAYS AS ($generated-as) STORED";
      }
      elsif $has-default {
        $col ~= ' DEFAULT ' ~ self!default-literal($default-value);
      }

      $col ~= self.ref-null-clause($null);

      @comments.push($field_name => $comment) if $comment.defined;

      @fields.push($col);
    }

    @fields;
  }
}
