
role SqlDdl is export {
  method ddl-drop-table(Str:D $table) {
    self.exec("DROP TABLE $table");
  }

  # Drop every table the adapter can see. Adapters override to disable FK
  # checks for the duration of the drops so order does not matter.
  method ddl-drop-all-tables(--> List) {
    my @tables = self.get-table-names.list;
    self.ddl-drop-table($_) for @tables;
    @tables;
  }

  method ddl-remove-column(Str:D $table, $field) {
    self.exec("ALTER TABLE $table DROP COLUMN $field");
  }

  method ddl-remove-timestamps(Str:D $table) {
    self.exec("ALTER TABLE $table DROP COLUMN created_at, DROP COLUMN updated_at");
  }

  method ddl-add-index(Str:D $table, Str:D :$name, Str:D :$columns, Bool:D :$unique = False) {
    my $u = $unique ?? 'UNIQUE ' !! '';
    self.exec("CREATE {$u}INDEX $name ON $table ($columns)");
  }

  method ddl-remove-index(Str:D :$name) {
    self.exec("DROP INDEX $name");
  }

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

  method ref-default-check-name(Str:D $table, Str:D $expression --> Str) {
    "chk_{$table}_" ~ self.ref-expr-hash($expression);
  }

  method ref-default-unique-name(Str:D $table, @columns --> Str) {
    "uq_{$table}_" ~ @columns.join('_');
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
