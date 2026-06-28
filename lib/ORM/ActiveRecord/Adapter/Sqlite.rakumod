
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

class SqliteAdapter is SqlAdapter is export {
  has Str  $.database = ':memory:';
  has Bool $!supports-returning = False;
  has Str  $.sqlite-version;

  submethod BUILD(Str :$!database = ':memory:') {
    self.connect;
  }

  submethod DESTROY {
    self.disconnect;
  }

  method connect() {
    return if self.db.defined;
    self.db = DBIish.connect('SQLite', :$!database);
    self.db.do('PRAGMA foreign_keys = ON');
    my $rows = self.db.prepare('SELECT sqlite_version()').execute.allrows;
    $!sqlite-version = $rows[0][0].Str;
    $!supports-returning = self!version-ge($!sqlite-version, '3.35.0');
  }

  method !version-ge(Str:D $a, Str:D $b --> Bool) {
    my @aa = $a.split('.').map: *.Int;
    my @bb = $b.split('.').map: *.Int;
    for ^max(+@aa, +@bb) -> $i {
      my $av = @aa[$i] // 0;
      my $bv = @bb[$i] // 0;
      return True  if $av > $bv;
      return False if $av < $bv;
    }
    True;
  }

  method bind-placeholder(Int:D $n --> Str) { '?' }

  # SQLite has no SQL-standard isolation levels — validated upstream, dropped here.
  method begin-sql(Str :$isolation) {
    self.txn-exec('BEGIN');
  }

  method explain(SqlStmt:D $stmt --> Str) {
    my $explain-stmt = SqlStmt.new(:adapter(self));
    $explain-stmt.sql = 'EXPLAIN QUERY PLAN ' ~ $stmt.sql;
    $explain-stmt.binds = $stmt.binds;
    my @rows = self.exec-stmt($explain-stmt);
    @rows.map({ $_.list.map(*.Str).join(' | ') }).join("\n");
  }

  method limit-offset-clause(Int:D :$limit = 0, Int:D :$offset = 0 --> Str) {
    return '' unless $limit || $offset;
    my $l = $limit ?? $limit !! -1;
    "LIMIT $l OFFSET $offset";
  }

  # SQLite locks the whole DB at the transaction level — no row-lock clause.
  method format-lock-clause($lock --> Str) { '' }

  method coerce-read($value, Str :$type) {
    return $value without $value;
    return $value unless $type.defined;
    given $type {
      when /:i ^ bool / {
        return $value if $value ~~ Bool;
        return $value.Int.Bool;
      }
      when /:i timestamp | datetime | ^ date | ^ time / {
        return $value if $value ~~ DateTime | Date;
        my $s = $value.Str;
        return $value unless $s;
        my $iso = $s.subst(' ', 'T');
        return DateTime.new($iso) if $iso ~~ /^ \d ** 4 '-' \d\d '-' \d\d 'T' \d\d ':' \d\d ':' \d\d /;
        return Date.new($s)       if $s ~~ /^ \d ** 4 '-' \d\d '-' \d\d $/;
        $value;
      }
      when /:i ^ int / {
        return $value if $value ~~ Int;
        return $value.Str.Int if $value.Str ~~ /^ '-'? \d+ $/;
        $value;
      }
      when /:i ^ real | ^ numeric | ^ decimal | ^ float | ^ double / {
        return $value if $value ~~ Numeric;
        return $value.Str.Numeric if $value.Str ~~ /^ '-'? \d+ ('.' \d+)? $/;
        $value;
      }
      default { $value }
    }
  }

  method coerce-write($value, Str :$type) {
    return $value without $value.defined;
    return $value unless $type.defined;
    given $type {
      when /:i ^ bool / {
        return $value.Int if $value ~~ Bool;
        return $value if $value ~~ Int;
        my $s = $value.Str.lc;
        return 1 if $s eq 'true' | 't' | '1' | 'y' | 'yes';
        return 0 if $s eq 'false'| 'f' | '0' | 'n' | 'no';
        $value;
      }
      when /:i timestamp | datetime | ^ date | ^ time / {
        if $value ~~ DateTime {
          my $iso = $value.utc.Str;
          $iso ~~ s/'T'/ /;
          $iso ~~ s/'Z'$//;
          $iso ~~ s/'+00:00'$//;
          return $iso;
        }
        return $value.Str if $value ~~ Date;
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

    my $returning = $!supports-returning ?? "\nRETURNING id" !! '';
    $stmt.sql = "INSERT INTO $table ($fields) VALUES ($values)$returning";

    $stmt;
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs-to-persist;
    my %types = self!types-from-fields($obj);
    my $stmt  = self.build-insert(:$table, :%attrs, :%types);

    my $rows = self.exec-stmt($stmt);
    if $!supports-returning && $rows.elems {
      return $rows[0][0].Int;
    }
    self.exec('SELECT last_insert_rowid()')[0][0].Int;
  }

  method !types-from-fields(Mu:D $obj) {
    my %types;
    for $obj.fields -> $f { %types{$f.name} = $f.type }
    %types;
  }

  method get-fields(Str:D :$table) {
    # PRAGMA table_info columns: cid, name, type, notnull, dflt_value, pk.
    # Lowercase the type to match PG's information_schema vocabulary.
    my $rows = self.exec("PRAGMA table_info('$table')");
    my @out;
    for @$rows -> $row {
      my $col-type = ($row[2] // '').Str.lc;
      $col-type = 'integer' unless $col-type;  # untyped column → INTEGER affinity
      @out.push: [$row[1], $col-type];
    }
    @out;
  }

  method column-details(Str:D :$table) {
    my $rows = self.exec("PRAGMA table_info('$table')");
    my @out;
    for @$rows -> $row {
      my $col-type = ($row[2] // '').Str.lc;
      $col-type = 'integer' unless $col-type;
      @out.push: %(
        name        => $row[1].Str,
        type        => $col-type,
        null        => !($row[3].Int),
        default     => ($row[4].defined ?? $row[4].Str !! Str),
        primary-key => $row[5].Int > 0,
      );
    }
    @out;
  }

  method get-table-names {
    my $rows = self.exec(qq:to/SQL/);
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
      SQL
    @$rows.map({ $_[0] });
  }

  # PRAGMA index_list: (seq, name, unique, origin, partial)
  # PRAGMA index_info: (seqno, cid, name)
  method get-indexes(Str:D :$table --> List) {
    my @triples;
    # Materialise the outer PRAGMA before issuing the per-index PRAGMA below;
    # iterating a live SQLite statement while running a nested query holds a
    # read lock that would block a later DROP TABLE.
    my @list = self.exec("PRAGMA index_list('$table')").list;
    for @list -> $ix {
      my $name   = $ix[1].Str;
      my $unique = so $ix[2].Int;
      my @cols   = self.exec("PRAGMA index_info('$name')").list;
      if @cols.elems {
        @triples.push: ($name, $unique, $_[2].Str) for @cols;
      } else {
        @triples.push: ($name, $unique, Str);
      }
    }
    self.ref-group-index-rows(@triples);
  }

  # SQLite exposes constraints through pragmas: foreign keys, the primary key,
  # and user-defined UNIQUE constraints (index_list origin 'u'). CHECK
  # constraints are not introspectable without parsing the table DDL.
  method get-constraints(Str:D :$table --> List) {
    my @out;

    my %seen-fk;
    for self.exec("PRAGMA foreign_key_list('$table')") -> $fk {
      next if %seen-fk{$fk[0].Str}++;
      @out.push: %( name => "fk_{$table}_{$fk[3].Str}", type => 'foreign-key' );
    }

    @out.push(%( name => "{$table}_pkey", type => 'primary-key' ))
      if self.exec("PRAGMA table_info('$table')").grep({ $_[5].Int > 0 }).elems;

    for self.exec("PRAGMA index_list('$table')") -> $ix {
      @out.push: %( name => $ix[1].Str, type => 'unique' ) if $ix[3].Str eq 'u';
    }

    @out;
  }

  # PRAGMA foreign_key_list: (id, seq, table, from, to, on_update, on_delete,
  # match). SQLite FKs are anonymous, so the name matches ref-default-fk-name.
  # `to` is NULL when the FK targets the referenced table's implicit primary
  # key, which is 'id' for tables this library creates.
  method get-foreign-keys(Str:D :$table --> List) {
    my @out;
    for self.exec("PRAGMA foreign_key_list('$table')") -> $fk {
      next unless $fk[1].Int == 0;
      my $column = $fk[3].Str;
      @out.push: %(
        name        => "fk_{$table}_{$column}",
        column      => $column,
        to-table    => $fk[2].Str,
        primary-key => ($fk[4].defined ?? $fk[4].Str !! 'id'),
        on-update   => self.ref-fk-action-keyword($fk[5].Str),
        on-delete   => self.ref-fk-action-keyword($fk[6].Str),
      );
    }
    @out.sort(*.<name>).list;
  }

  # SQLite has no sequences; AUTOINCREMENT bookkeeping lives in sqlite_sequence.
  method get-sequences(--> List) {
    my $exists = self.exec(q{SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence'});
    return () unless @$exists.elems;
    self.exec('SELECT name FROM sqlite_sequence ORDER BY name').map({ $_[0].Str }).list;
  }

  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    return @tables unless @tables.elems;
    self.exec('PRAGMA foreign_keys = OFF');
    LEAVE self.exec('PRAGMA foreign_keys = ON');
    self.exec("DROP TABLE IF EXISTS {$_}") for @tables;
    @tables;
  }

  method delete-records(Str:D :$table, :%where, :%where-not) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $where-sql = self.build-where($stmt, %where, %where-not);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    $stmt.sql = "DELETE FROM $table $where-clause";
    self.exec-stmt($stmt);
    self.exec('SELECT changes()')[0][0].Int;
  }

  method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
    my $stmt = self.build-update-where(:$table, :%attrs, :%types, :%where, :%where-not, :@or-groups, :@locking-bump);
    self.exec-stmt($stmt);
    self.exec('SELECT changes()')[0][0].Int;
  }

  method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
    my $stmt = self.build-update-counters-where(:$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump);
    self.exec-stmt($stmt);
    self.exec('SELECT changes()')[0][0].Int;
  }

  method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List) {
    my $stmt = self.build-insert-many(:$table, :@rows, :%types);
    if $skip-conflict {
      $stmt.sql ~= ' ON CONFLICT DO NOTHING';
    }
    if $!supports-returning {
      $stmt.sql ~= ' RETURNING id';
      self.exec-stmt($stmt).map({ .[0].Int }).list;
    } else {
      self.exec-stmt($stmt);
      my $last = self.exec('SELECT last_insert_rowid()')[0][0].Int;
      my $first = $last - @rows.elems + 1;
      ($first .. $last).list;
    }
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
      my $set-list = @update.map({ "$_ = excluded.$_" }).join(', ');
      $stmt.sql ~= " ON CONFLICT($conflict-list) DO UPDATE SET $set-list";
    } else {
      $stmt.sql ~= " ON CONFLICT($conflict-list) DO NOTHING";
    }
    self.exec-stmt($stmt);
    self.exec('SELECT changes()')[0][0].Int;
  }

  # ---- DDL emission ----

  method ddl-create-table(Str:D $table, @params,
                          :$force, Bool :$temporary = False, Bool :$if-not-exists = False,
                          :$id = True, :$primary-key, :$comment) {
    self.ddl-force-drop($table, $force);

    my %pk = self.pk-plan(:$id, :$primary-key);
    my @fk-clauses;
    my @field-defs = self!build-fields(@params, :@fk-clauses);
    my $prefix = self.ref-create-table-prefix(:$temporary, :$if-not-exists);

    my @cols;
    my Bool $inline-pk = False;

    if %pk<emit-id-col> {
      # INTEGER PRIMARY KEY AUTOINCREMENT couples the column and the key, so it
      # only applies to a single integer surrogate; other types take a separate
      # table-level PRIMARY KEY constraint below.
      if %pk<id-type> eq 'integer' && %pk<pk-cols>.elems == 1 {
        @cols.push("{%pk<pk-name>} INTEGER PRIMARY KEY AUTOINCREMENT");
        $inline-pk = True;
      }
      else {
        @cols.push("{%pk<pk-name>} {self!sqlite-id-type(%pk<id-type>)}");
      }
    }

    @cols.append(@field-defs);
    @cols.push("PRIMARY KEY ({%pk<pk-cols>.join(', ')})") if %pk<want-pk> && !$inline-pk;
    @cols.append(@fk-clauses);

    self.exec("{$prefix}$table ( {@cols.join(', ')} )");
    # SQLite has no table comments — `:comment` is accepted for cross-adapter
    # parity and ignored.
  }

  method !sqlite-id-type(Str:D $type --> Str) {
    given $type {
      when 'uuid' | 'string' | 'text' { 'TEXT' }
      default                         { self.ref-sql-type($type) }
    }
  }

  method ddl-add-column(Str:D $table, Pair:D $param, Bool :$if-not-exists = False) {
    my $clause = $if-not-exists ?? self.ref-column-if-not-exists-clause !! '';
    # SQLite ALTER TABLE can't add FK constraints — use create-table for enforced FKs.
    for self.ddl-column-defs($param) -> $col {
      self.exec("ALTER TABLE $table ADD COLUMN {$clause}$col");
    }
  }

  method ddl-column-defs(Pair:D $param --> List) {
    my @fk-clauses;
    self!build-fields([$param], :@fk-clauses);
  }

  # SQLite's ALTER TABLE allows only one column operation per statement, so a
  # bulk change-table can't be coalesced — run each clause on its own.
  method ddl-alter-table-bulk(Str:D $table, @clauses) {
    self.exec("ALTER TABLE $table $_") for @clauses;
  }

  method ddl-change-column(Str:D $table, Str:D $name, Str:D $type, *%opts) {
    die 'SqliteAdapter: change-column is not supported (SQLite has no ALTER COLUMN; rebuild the table manually)';
  }

  method ddl-change-column-default(Str:D $table, Str:D $name, $value) {
    die 'SqliteAdapter: change-column-default is not supported (SQLite has no ALTER COLUMN; rebuild the table manually)';
  }

  method ddl-change-column-null(Str:D $table, Str:D $name, Bool:D $null, :$default) {
    die 'SqliteAdapter: change-column-null is not supported (SQLite has no ALTER COLUMN; rebuild the table manually)';
  }

  method ddl-change-column-comment(Str:D $table, Str:D $name, $comment) {
    # SQLite has no concept of column comments — silently no-op so cross-adapter
    # migrations don't fail. Use a dedicated comment table if you need parity.
  }

  method ddl-change-table-comment(Str:D $table, $comment) {
    # SQLite has no concept of table comments — silently no-op.
  }

  method ddl-add-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table ADD COLUMN created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP");
    self.exec("ALTER TABLE $table ADD COLUMN updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP");
  }

  method ref-text-sql-type(--> Str) { 'TEXT' }

  method ref-sql-type(Str:D $type --> Str) {
    given $type {
      when 'integer' | 'bigint' | 'smallint' { 'INTEGER' }
      default { $type.uc }
    }
  }

  # SQLite has no ALTER INDEX rename. Look up the existing CREATE statement,
  # drop it, and recreate with the new identifier swapped in.
  method ddl-rename-index(Str:D $table, Str:D $from, Str:D $to) {
    my $rows = self.exec("SELECT sql FROM sqlite_master WHERE type='index' AND name='$from'");
    die "SqliteAdapter: no such index '$from'" unless $rows.elems && $rows[0][0].defined;

    my $sql = $rows[0][0].Str;
    self.exec("DROP INDEX $from");
    my $new-sql = $sql.subst(/INDEX \s+ "$from"/, "INDEX $to");
    self.exec($new-sql);
  }

  # SQLite supports partial (WHERE) and expression indexes, but not access
  # methods (USING), covering INCLUDE, CONCURRENTLY, or operator classes.
  method ref-index-algorithm-keyword($algorithm --> Str) {
    return '' without $algorithm;
    die 'SqliteAdapter: index algorithm (e.g. CONCURRENTLY) is not supported';
  }

  method ref-index-using-prefix(Str:D $using --> Str) {
    die 'SqliteAdapter: index USING method is not supported';
  }

  method ref-index-include-clause($include --> Str) {
    die 'SqliteAdapter: covering index INCLUDE is not supported';
  }

  method ref-index-supports-opclass(--> Bool) { False }

  method ref-supports-alter-foreign-key(--> Bool) { False }

  method ddl-add-foreign-key(Str:D $from-table, Str:D $to-table, *%opts) {
    die 'SqliteAdapter: add-foreign-key on an existing table is not supported (SQLite needs a table rebuild; declare the FK in create-table instead)';
  }

  method ddl-remove-foreign-key(Str:D $from-table, *%opts) {
    die 'SqliteAdapter: remove-foreign-key on an existing table is not supported (SQLite needs a table rebuild)';
  }

  method ddl-add-check-constraint(Str:D $table, Str:D $expression, *%opts) {
    die 'SqliteAdapter: add-check-constraint on an existing table is not supported (SQLite needs a table rebuild; declare the CHECK in create-table instead)';
  }

  method ddl-remove-check-constraint(Str:D $table, *%opts) {
    die 'SqliteAdapter: remove-check-constraint on an existing table is not supported (SQLite needs a table rebuild)';
  }

  method ddl-add-unique-constraint(Str:D $table, *%opts) {
    die 'SqliteAdapter: add-unique-constraint via ALTER TABLE is not supported (use add-index :unique => True instead)';
  }

  method ddl-remove-unique-constraint(Str:D $table, *%opts) {
    die 'SqliteAdapter: remove-unique-constraint via ALTER TABLE is not supported (use remove-index instead)';
  }

  method ddl-remove-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table DROP COLUMN created_at");
    self.exec("ALTER TABLE $table DROP COLUMN updated_at");
  }

  method !default-literal($value --> Str) {
    return 'NULL' without $value;
    return $value().Str if $value ~~ Callable;
    return ($value ?? '1' !! '0') if $value ~~ Bool;
    return $value.Str if $value ~~ Numeric;
    self!string-literal($value.Str);
  }

  method !string-literal(Str:D $s --> Str) {
    "'" ~ $s.subst("'", "''", :g) ~ "'";
  }

  method !build-fields(@params, :@fk-clauses) {
    my @fields;

    for @params {
      my $name = $_.keys.first;
      my $field_name = $name ~~ Pair ?? $name.keys.first !! $name;

      my Bool $is-reference   = $_{$name}<reference>:exists;
      my Bool $is-polymorphic = ($_{$name}<polymorphic>:exists) && $_{$name}<polymorphic>.so;

      if $is-reference && $is-polymorphic {
        @fields.push($field_name ~ '_id INTEGER');
        @fields.push($field_name ~ '_type TEXT');
        next;
      }

      my $type = '';
      my $null = '';
      my Bool $is-bool = False;
      my Bool $has-default = False;
      my $default-value;
      my $collation;
      my $generated-as;
      my Bool $stored = False;
      my Bool $is-unique = False;
      my $references;
      my $fk-on-delete;
      my $fk-on-update;
      my $fk-name;
      my $fk-primary-key = 'id';

      for $_{$name}.keys -> $attr {
        my $value = $_{$name}{$attr};

        given $attr {
          when 'string'  { $type = 'TEXT' }
          when 'text'    { $type = 'TEXT' }
          when 'integer' { $type = 'INTEGER' }
          when 'bigint'  { $type = 'INTEGER' }
          when 'smallint' { $type = 'INTEGER' }
          when 'boolean' { $type = 'BOOLEAN'; $is-bool = True }
          when 'decimal' | 'numeric' { $type = 'NUMERIC' }
          when 'float'   { $type = 'REAL' }
          when 'money'   { $type = 'NUMERIC' }
          when 'datetime' | 'timestamp' { $type = 'DATETIME' }
          when 'timestamptz' { $type = 'DATETIME' }
          when 'date'    { $type = 'DATE' }
          when 'time'    { $type = 'TIME' }
          when 'interval' { die 'SqliteAdapter: :interval columns are PostgreSQL-only' }
          when 'uuid'    { $type = 'TEXT' }
          when 'binary'  { $type = 'BLOB' }
          when 'json'    { $type = 'JSON' }     # stored as text; json1 functions apply
          when 'jsonb'   { $type = 'JSON' }
          when 'hstore'  { die 'SqliteAdapter: :hstore columns are PostgreSQL-only' }
          when 'xml'     { die 'SqliteAdapter: :xml columns are PostgreSQL-only' }
          when 'array' | 'ltree' | 'inet' | 'cidr' | 'macaddr'
             | 'int4range' | 'int8range' | 'numrange' | 'tsrange' | 'tstzrange' | 'daterange'
             | 'point' | 'line' | 'lseg' | 'box' | 'path' | 'polygon' | 'circle'
             | 'tsvector' | 'tsquery' | 'bit' | 'bit_varying' | 'citext' | 'enum_type' {
            die "SqliteAdapter: :$attr columns are PostgreSQL-only";
          }
          # SQLite uses type affinity, so size / precision / scale are ignored.
          when 'limit'     { }
          when 'precision' { }
          when 'scale'     { }
          when 'default'   { $has-default = True; $default-value = $value }
          when 'null'      { $null = $value }
          when 'unique'    { $is-unique = $value.so }
          when 'collation' { $collation = $value }
          when 'charset'   { }   # SQLite has no charset; ignored for parity
          when 'as'        { $generated-as = $value }
          when 'stored'    { $stored = $value.so }
          when 'virtual'   { }
          when 'comment'   { }   # SQLite has no column comments; ignored
          when 'reference' {
            $type = 'INTEGER';
            $field_name = $field_name ~ '_id';
            @fk-clauses.push("FOREIGN KEY ($field_name) REFERENCES { $name ~ 's' }(id)");
          }
          when 'references'     { $references = $value }
          when 'on-delete'      { $fk-on-delete = $value }
          when 'on-update'      { $fk-on-update = $value }
          when 'fk-name'        { $fk-name = $value }
          when 'fk-primary-key' { $fk-primary-key = $value }
          default { die 'SqliteAdapter: unknown column attr: ' ~ $attr }
        }
      }

      my $col = "$field_name $type";

      $col ~= ' COLLATE ' ~ $collation if $collation.defined;

      if $generated-as.defined {
        my $kind = $stored ?? 'STORED' !! 'VIRTUAL';
        $col ~= " GENERATED ALWAYS AS ($generated-as) $kind";
      }
      elsif $has-default {
        $col ~= ' DEFAULT ' ~ self!default-literal($default-value);
      }

      $col ~= self.ref-null-clause($null);
      $col ~= ' UNIQUE' if $is-unique;

      @fields.push($col);

      if $references.defined {
        my $constraint = $fk-name.defined
          ?? "CONSTRAINT $fk-name "
          !! '';
        my $on-del = $fk-on-delete.defined
          ?? ' ON DELETE ' ~ self.ref-fk-action($fk-on-delete) !! '';
        my $on-upd = $fk-on-update.defined
          ?? ' ON UPDATE ' ~ self.ref-fk-action($fk-on-update) !! '';
        @fk-clauses.push(
          "{$constraint}FOREIGN KEY ($field_name) REFERENCES {$references}({$fk-primary-key})$on-del$on-upd");
      }
    }

    @fields;
  }
}
