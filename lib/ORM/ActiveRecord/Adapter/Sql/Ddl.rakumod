
role SqlDdl is export {
  method ddl-drop-table(Str:D $table, Bool :$if-exists = False, Bool :$cascade = False) {
    my $ie = $if-exists ?? 'IF EXISTS ' !! '';
    my $cc = $cascade   ?? self.ref-drop-cascade-suffix !! '';
    self.exec("DROP TABLE {$ie}{$table}{$cc}");
  }

  # Drop every table the adapter can see. Adapters override to disable FK
  # checks for the duration of the drops so order does not matter.
  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    self.ddl-drop-table($_) for @tables;
    @tables;
  }

  # `force: True` drops the table first; `force: 'cascade'` adds CASCADE where
  # the adapter supports it. The drop is IF EXISTS so a fresh table is fine.
  method ddl-force-drop(Str:D $table, $force) {
    return without $force;
    return if $force ~~ Bool && !$force;

    my Bool $cascade = $force ~~ Str && $force.lc eq 'cascade';
    self.ddl-drop-table($table, :if-exists, :$cascade);
  }

  method ref-drop-cascade-suffix(--> Str) { '' }

  # CREATE [TEMPORARY] TABLE [IF NOT EXISTS] — TEMPORARY and IF NOT EXISTS are
  # accepted by all three engines, so the prefix lives in the shared role and
  # each adapter only fills in the body (id column, engine, etc.).
  method ref-create-table-prefix(Bool :$temporary = False, Bool :$if-not-exists = False --> Str) {
    my $temp = $temporary    ?? self.ref-temporary-keyword !! '';
    my $ine  = $if-not-exists ?? 'IF NOT EXISTS '          !! '';
    "CREATE {$temp}TABLE {$ine}";
  }

  method ref-temporary-keyword(--> Str) { 'TEMPORARY ' }

  # Resolve the `id:` / `primary-key:` create-table options into a plan the
  # adapters emit from. Semantics mirror Rails:
  #   id => True (default)  surrogate auto-increment integer named 'id'
  #   id => 'uuid'          surrogate column of that type (custom PK type)
  #   id => False           no surrogate column
  #   primary-key => 'guid' rename the surrogate column / PK
  #   primary-key => False  no PRIMARY KEY at all
  #   primary-key => [a, b] composite PRIMARY KEY over already-declared columns
  method pk-plan(:$id = True, :$primary-key) {
    my Bool $composite = $primary-key ~~ Positional;
    my Bool $id-false  = $id === False;

    my Str $pk-name = $primary-key ~~ Str:D ?? $primary-key.Str !! 'id';

    my Str $id-type = do given $id {
      when Bool { 'integer' }
      when Pair { $id.key.Str.lc }
      when Str  { $id.lc }
      default   { $id.defined ?? $id.Str.lc !! 'integer' }
    };

    my Bool $emit-id-col = !$id-false && !$composite;

    my Bool $want-pk = do {
      if    $composite             { True }
      elsif $primary-key === False { False }
      elsif $id-false              { $primary-key ~~ Str:D }
      else                         { True }
    };

    my @pk-cols = $composite
      ?? $primary-key.map(*.Str).list
      !! ($want-pk ?? ($pk-name,) !! ());

    %( :$emit-id-col, :$pk-name, :$id-type, :$want-pk, :@pk-cols );
  }

  # A join table is just two NOT NULL foreign-key columns and no primary key.
  # Name and column names are derived in the migration layer.
  method ddl-create-join-table(Str:D $table, Str:D $col1, Str:D $col2,
                               Bool :$null = False,
                               Str  :$type = 'integer') {
    my $sql-type    = self.ref-sql-type($type);
    my $null-clause = $null ?? '' !! ' NOT NULL';

    self.exec("CREATE TABLE $table ( $col1 $sql-type$null-clause, $col2 $sql-type$null-clause )");
  }

  method ddl-drop-join-table(Str:D $table, Bool :$if-exists = False) {
    self.ddl-drop-table($table, :$if-exists);
  }

  # Coalesced ALTER TABLE for change-table(:bulk). Clauses are pre-built
  # ADD COLUMN / DROP COLUMN fragments joined into one statement.
  method ddl-alter-table-bulk(Str:D $table, @clauses) {
    self.exec("ALTER TABLE $table " ~ @clauses.join(', '));
  }

  method ddl-remove-column(Str:D $table, $field, Bool :$if-exists = False) {
    my $clause = $if-exists ?? self.ref-column-if-exists-clause !! '';
    self.exec("ALTER TABLE $table DROP COLUMN {$clause}$field");
  }

  # Column-level IF [NOT] EXISTS is PostgreSQL-only; the generic role raises so
  # MySQL / SQLite fail loudly rather than emit broken SQL.
  method ref-column-if-not-exists-clause(--> Str) {
    die "add-column: if-not-exists is not supported on this adapter ({self.^name})";
  }
  method ref-column-if-exists-clause(--> Str) {
    die "remove-column: if-exists is not supported on this adapter ({self.^name})";
  }

  method ddl-remove-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table DROP COLUMN created_at, DROP COLUMN updated_at");
  }

  method ddl-add-index(Str:D $table,
                       Str:D :$name,
                       :$columns,
                       Bool:D :$unique = False,
                       :$expression,
                       :$where, :$using, :$include, :$algorithm,
                       Bool :$if-not-exists = False) {

    my $u    = $unique ?? 'UNIQUE ' !! '';
    my $conc = self.ref-index-algorithm-keyword($algorithm);
    my $ine  = $if-not-exists ?? self.ref-index-if-not-exists-clause !! '';

    my $use-pre  = $using.defined ?? self.ref-index-using-prefix($using) !! '';
    my $use-post = $using.defined ?? self.ref-index-using-suffix($using) !! '';

    my $body = $expression.defined
      ?? self.ref-index-expression-body($expression)
      !! $columns;

    my $incl = $include.defined ?? self.ref-index-include-clause($include) !! '';
    my $wh   = $where.defined   ?? self.ref-index-where-clause($where)     !! '';

    self.exec("CREATE {$u}INDEX {$conc}{$ine}{$name} ON {$table}{$use-pre} ({$body}){$incl}{$use-post}{$wh}");
  }

  method ddl-remove-index(Str:D :$name, Str :$table, :$algorithm, Bool :$if-exists = False) {
    my $conc = self.ref-index-algorithm-keyword($algorithm);
    my $ife  = $if-exists ?? self.ref-index-if-exists-clause !! '';
    self.exec("DROP INDEX {$conc}{$ife}$name");
  }

  # CREATE / DROP INDEX IF [NOT] EXISTS works on PostgreSQL and SQLite; MySQL
  # overrides these to raise.
  method ref-index-if-not-exists-clause(--> Str) { 'IF NOT EXISTS ' }
  method ref-index-if-exists-clause(--> Str)     { 'IF EXISTS ' }

  # Per-adapter index capability hooks. Base shape is PostgreSQL; SQLite and
  # MySQL override the clauses they do not support to raise a clear error.
  method ref-index-algorithm-keyword($algorithm --> Str) {
    return '' without $algorithm;

    given $algorithm.Str.lc {
      when 'concurrently' { 'CONCURRENTLY ' }
      default { die "add-index: unsupported algorithm '$algorithm'" }
    }
  }

  method ref-index-using-prefix(Str:D $using --> Str) { " USING {$using.lc}" }
  method ref-index-using-suffix(Str:D $using --> Str) { '' }

  method ref-index-include-clause($include --> Str) {
    my @cols = self.ref-columns-list($include);
    " INCLUDE ({@cols.join(', ')})";
  }

  method ref-index-where-clause(Str:D $where --> Str) { " WHERE $where" }
  method ref-index-expression-body(Str:D $expression --> Str) { $expression }
  method ref-index-supports-opclass(--> Bool) { True }

  method ddl-rename-table(Str:D $from, Str:D $to) {
    self.exec("ALTER TABLE $from RENAME TO $to");
  }

  method ddl-rename-column(Str:D $table, Str:D $from, Str:D $to) {
    self.exec("ALTER TABLE $table RENAME COLUMN $from TO $to");
  }

  method ddl-rename-index(Str:D $table, Str:D $from, Str:D $to) {
    self.exec("ALTER INDEX $from RENAME TO $to");
  }

  # References share a single ALTER-TABLE shape for the column(s); PG/MySQL
  # also share an ALTER-TABLE shape for the FK constraint. SQLite overrides
  # the FK paths because ALTER TABLE can't add or drop FKs there.
  method ddl-add-reference(Str:D $table, Str:D $name,
                           Bool :$polymorphic = False,
                           Bool :$null,
                           Bool :$index = True,
                           Bool :$unique = False,
                           Bool :$foreign-key = False,
                           Str  :$to-table,
                           Str  :$type = 'integer',
                           :$on-delete, :$on-update,
                           Str  :$fk-name) {

    my $sql-type = self.ref-sql-type($type);

    my Bool $null-flag = $null.defined ?? $null.so !! True;
    my $null-clause = $null-flag ?? '' !! ' NOT NULL';

    self.exec("ALTER TABLE $table ADD COLUMN {$name}_id $sql-type$null-clause");

    if $polymorphic {
      my $text-type = self.ref-text-sql-type;
      self.exec("ALTER TABLE $table ADD COLUMN {$name}_type $text-type$null-clause");
    }

    if $index {
      my @cols = $polymorphic
        ?? ("{$name}_type", "{$name}_id")
        !! ("{$name}_id",);
      my $idx-cols = @cols.join(', ');
      my $idx-name = self.ref-index-name($table, $name, :$polymorphic);
      self.ddl-add-index($table, name => $idx-name, columns => $idx-cols, :$unique);
    }

    if $foreign-key && !$polymorphic {
      my $target = $to-table // self.ref-default-to-table($name);
      self.ddl-add-foreign-key(
        $table, $target,
        column => "{$name}_id",
        |(:$on-delete with $on-delete),
        |(:$on-update with $on-update),
        |(:name($fk-name) with $fk-name),
      );
    }
  }

  method ddl-remove-reference(Str:D $table, Str:D $name,
                              Bool :$polymorphic = False,
                              Bool :$index = True,
                              Bool :$foreign-key = False,
                              Str  :$to-table,
                              Str  :$fk-name,
                              *%) {

    if $foreign-key && !$polymorphic {
      my $target = $to-table // self.ref-default-to-table($name);
      self.ddl-remove-foreign-key(
        $table,
        :to-table($target),
        column => "{$name}_id",
        |(:name($fk-name) with $fk-name),
      );
    }

    if $index {
      my $idx-name = self.ref-index-name($table, $name, :$polymorphic);
      try { self.ddl-remove-index(:name($idx-name)) };
    }

    self.ddl-remove-column($table, "{$name}_type") if $polymorphic;
    self.ddl-remove-column($table, "{$name}_id");
  }

  method ddl-add-foreign-key(Str:D $from-table, Str:D $to-table,
                             Str  :$column,
                             Str  :$primary-key = 'id',
                             Str  :$name,
                             Str  :$on-delete,
                             Str  :$on-update,
                             Bool :$validate = True) {

    my $col    = $column // self.ref-default-column($to-table);
    my $fkname = $name // self.ref-default-fk-name($from-table, $col);
    my $on-del = $on-delete.defined ?? ' ON DELETE ' ~ self.ref-fk-action($on-delete) !! '';
    my $on-upd = $on-update.defined ?? ' ON UPDATE ' ~ self.ref-fk-action($on-update) !! '';
    my $not-valid = $validate ?? '' !! self.ref-fk-not-valid-suffix;

    self.exec(qq:to/SQL/);
      ALTER TABLE $from-table
      ADD CONSTRAINT $fkname
      FOREIGN KEY ($col)
      REFERENCES $to-table ($primary-key)$on-del$on-upd$not-valid
      SQL
  }

  method ddl-remove-foreign-key(Str:D $from-table,
                                Str  :$to-table,
                                Str  :$column,
                                Str  :$name) {
    my $fkname = $name // do {
      die 'remove-foreign-key: pass :name or :to-table' unless $to-table.defined;
      my $col = $column // self.ref-default-column($to-table);
      self.ref-default-fk-name($from-table, $col);
    };
    self.exec("ALTER TABLE $from-table DROP CONSTRAINT $fkname");
  }

  method ddl-validate-foreign-key(Str:D $table, Str:D $name) {
    # Only PG distinguishes pending validation; other adapters always validate
    # on add, so this is a no-op there.
  }

  method ddl-add-check-constraint(Str:D $table, Str:D $expression,
                                  Str  :$name,
                                  Bool :$validate = True) {
    my $cname    = $name // self.ref-default-check-name($table, $expression);
    my $not-valid = $validate ?? '' !! self.ref-check-not-valid-suffix;

    self.exec("ALTER TABLE $table ADD CONSTRAINT $cname CHECK ($expression)$not-valid");
  }

  method ddl-remove-check-constraint(Str:D $table,
                                     Str :$expression,
                                     Str :$name) {
    my $cname = $name // do {
      die 'remove-check-constraint: pass :name or :expression' unless $expression.defined;
      self.ref-default-check-name($table, $expression);
    };
    self.exec("ALTER TABLE $table DROP CONSTRAINT $cname");
  }

  method ddl-validate-check-constraint(Str:D $table, Str:D $name) {
    # Only PG distinguishes pending validation; other adapters always validate
    # on add, so this is a no-op there.
  }

  method ddl-add-unique-constraint(Str:D $table,
                                   :$columns,
                                   Str :$name,
                                   Bool :$deferrable = False,
                                   Bool :$initially-deferred = False) {
    my @cols = self.ref-columns-list($columns);
    die 'add-unique-constraint: :columns must be non-empty' unless @cols.elems;

    my $cname     = $name // self.ref-default-unique-name($table, @cols);
    my $col-list  = @cols.join(', ');
    my $deferr    = self.ref-unique-deferrable-suffix(:$deferrable, :$initially-deferred);

    self.exec("ALTER TABLE $table ADD CONSTRAINT $cname UNIQUE ($col-list)$deferr");
  }

  method ddl-remove-unique-constraint(Str:D $table,
                                      :$columns,
                                      Str :$name) {
    my @cols = self.ref-columns-list($columns);
    my $cname = $name // do {
      die 'remove-unique-constraint: pass :name or :columns' unless @cols.elems;
      self.ref-default-unique-name($table, @cols);
    };
    self.exec("ALTER TABLE $table DROP CONSTRAINT $cname");
  }

  method ref-columns-list($columns --> List) {
    return ()              without $columns;
    return ($columns,)     if $columns ~~ Str;
    $columns.list;
  }

  method ddl-add-exclusion-constraint(Str:D $table, Str:D $expression,
                                      Str  :$using = 'gist',
                                      Str  :$name,
                                      Str  :$where,
                                      Bool :$deferrable = False,
                                      Bool :$initially-deferred = False) {
    die "add-exclusion-constraint: not supported on this adapter ({self.^name})";
  }

  method ddl-remove-exclusion-constraint(Str:D $table,
                                         Str :$name) {
    die "remove-exclusion-constraint: not supported on this adapter ({self.^name})";
  }

  # PostgreSQL extensions and enums. Both are PG-specific concepts; the base
  # adapters raise so non-PG migrations fail loudly rather than silently doing
  # nothing. PgAdapter overrides each with real DDL.
  method ddl-enable-extension(Str:D $name) {
    die "enable-extension: not supported on this adapter ({self.^name})";
  }

  method ddl-disable-extension(Str:D $name, Bool :$cascade = False) {
    die "disable-extension: not supported on this adapter ({self.^name})";
  }

  method ddl-create-enum(Str:D $name, @values) {
    die "create-enum: not supported on this adapter ({self.^name})";
  }

  method ddl-drop-enum(Str:D $name, Bool :$if-exists = False) {
    die "drop-enum: not supported on this adapter ({self.^name})";
  }

  method ddl-add-enum-value(Str:D $name, Str:D $value,
                            Str :$before, Str :$after, Bool :$if-not-exists = False) {
    die "add-enum-value: not supported on this adapter ({self.^name})";
  }

  method ddl-rename-enum-value(Str:D $name, Str:D $from, Str:D $to) {
    die "rename-enum-value: not supported on this adapter ({self.^name})";
  }

  method ref-default-check-name(Str:D $table, Str:D $expression --> Str) {
    "chk_{$table}_" ~ self.ref-expr-hash($expression);
  }

  method ref-default-unique-name(Str:D $table, @columns --> Str) {
    "uq_{$table}_" ~ @columns.join('_');
  }

  # Fold per-(index, column) introspection rows into one hash per index.
  # Each triple is (index-name, unique-Bool, column-name); column order is the
  # order the triples arrive in.
  method ref-group-index-rows(@triples --> List) {
    my @order;
    my %by;
    for @triples -> ($name, $unique, $col) {
      unless %by{$name}:exists {
        %by{$name} = %( :$name, :$unique, columns => [] );
        @order.push($name);
      }
      %by{$name}<columns>.push($col) if $col.defined;
    }
    @order.map({ %by{$_} }).list;
  }

  method ref-expr-hash(Str:D $expr --> Str) {
    my Int $hash = 0;
    for $expr.comb -> $c {
      $hash = ($hash * 31 + $c.ord) % (2 ** 32);
    }
    $hash.fmt('%08x');
  }

  method ref-check-not-valid-suffix(--> Str) { '' }

  method ref-unique-deferrable-suffix(Bool :$deferrable = False, Bool :$initially-deferred = False --> Str) {
    return ''  unless $deferrable;
    return ' DEFERRABLE INITIALLY DEFERRED' if $initially-deferred;
    ' DEFERRABLE';
  }

  method ref-sql-type(Str:D $type --> Str) {
    given $type {
      when 'integer' { 'INTEGER' }
      when 'bigint'  { 'BIGINT' }
      default        { $type.uc }
    }
  }

  method ref-text-sql-type(--> Str) { 'VARCHAR(255)' }

  # NULL / NOT NULL clause from a column's `null` option. The raw value is a
  # Bool (or the empty string when the option was omitted); stringifying keeps
  # the same shape every adapter's build-fields used to inline.
  method ref-null-clause($null --> Str) {
    given $null {
      when 'True'  { ' NULL' }
      when 'False' { ' NOT NULL' }
      default      { '' }
    }
  }

  method ref-index-name(Str:D $table, Str:D $name, Bool :$polymorphic --> Str) {
    $polymorphic
      ?? "{$table}_{$name}_type_{$name}_id_idx"
      !! "{$table}_{$name}_id_idx";
  }

  method ref-default-to-table(Str:D $name --> Str) { $name ~ 's' }
  method ref-default-column(Str:D $to-table --> Str) {
    my $singular = $to-table.ends-with('s') ?? $to-table.chop !! $to-table;
    "{$singular}_id";
  }
  method ref-default-fk-name(Str:D $from-table, Str:D $column --> Str) {
    "fk_{$from-table}_{$column}";
  }

  method ref-fk-action(Str:D $action --> Str) {
    given $action.lc {
      when 'cascade'    { 'CASCADE' }
      when 'nullify'    { 'SET NULL' }
      when 'set_null' | 'set-null' { 'SET NULL' }
      when 'set_default' | 'set-default' { 'SET DEFAULT' }
      when 'restrict'   { 'RESTRICT' }
      when 'no_action' | 'no-action' { 'NO ACTION' }
      default { $action.uc }
    }
  }

  method ref-fk-not-valid-suffix(--> Str) { '' }
}
