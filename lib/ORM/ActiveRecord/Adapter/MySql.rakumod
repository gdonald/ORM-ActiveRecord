
use DBIish;

use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Adapter::Sql;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Support::Utils;

class MySqlAdapter is SqlAdapter is export {
  has Str $.host     = 'localhost';
  has Int $.port     = 3306;
  has Str $.database;
  has Str $.user;
  has Str $.password;
  has Str $.socket;

  submethod BUILD(
    Str :$!host     = 'localhost',
    Int :$!port     = 3306,
    Str :$!database,
    Str :$!user,
    Str :$!password,
    Str :$!socket,
  ) {
    self.connect;
  }

  submethod DESTROY {
    self.disconnect;
  }

  method connect() {
    return if self.db.defined;
    %*ENV<DBIISH_MYSQL_LIB> //= self!discover-libmysql;
    my %params = :$!host, :$!port, :$!database, :$!user, :$!password;
    %params<socket> = $!socket if $!socket.defined;
    self.db = DBIish.connect('mysql', |%params);
  }

  # DBDish::mysql's default search covers libmysqlclient versions 16..21 only.
  # Homebrew on Apple Silicon ships version 24 under /opt/homebrew/lib, which
  # also isn't on dyld's default search path — so the loader can't find it
  # even when widened to 0..99. Discover an absolute path on macOS and
  # fall back to the bare name 'mysqlclient' on Linux (where the dynamic
  # linker has the right paths and a wider version range is enough).
  method !discover-libmysql(--> Str) {
    for </opt/homebrew/opt/mysql-client/lib/libmysqlclient.dylib
    /opt/homebrew/opt/mysql/lib/libmysqlclient.dylib
    /opt/homebrew/lib/libmysqlclient.dylib
    /usr/local/opt/mysql-client/lib/libmysqlclient.dylib
    /usr/local/opt/mysql/lib/libmysqlclient.dylib
    /usr/local/lib/libmysqlclient.dylib
    /opt/homebrew/lib/libmariadb.dylib
    /usr/local/lib/libmariadb.dylib> -> $candidate {
      return $candidate if $candidate.IO.e;
    }
    'mysqlclient';
  }

  method bind-placeholder(Int:D $n --> Str) { '?' }

  # MySQL's default collation (utf8mb4_0900_ai_ci) makes `col = ?` compare
  # case-insensitively. Use BINARY to force a byte-level comparison when the
  # caller asks for case-sensitive matching.
  method case-eq-sql(Str:D $col, Bool:D :$case-sensitive --> Str) {
    $case-sensitive ?? "BINARY $col = ?" !! "LOWER($col) = LOWER(?)";
  }

  # MySQL doesn't accept ISOLATION LEVEL inside START TRANSACTION the way
  # PG accepts it in BEGIN; emit a separate SET TRANSACTION first.
  method begin-sql(Str :$isolation) {
    if $isolation.defined && $isolation.chars {
      my $level = self.normalise-isolation($isolation);
      self.txn-exec("SET TRANSACTION ISOLATION LEVEL $level");
    }
    self.txn-exec('START TRANSACTION');
  }

  method limit-offset-clause(Int:D :$limit = 0, Int:D :$offset = 0 --> Str) {
    return '' unless $limit || $offset;
    my $l = $limit ?? $limit !! 18446744073709551615;
    "LIMIT $l OFFSET $offset";
  }

  method quote-identifier(Str:D $name --> Str) {
    my $escaped = $name.subst('`', '``', :g);
    "`$escaped`";
  }

  method coerce-read($value is copy, Str :$type) {
    return $value without $value.defined;
    return $value unless $type.defined;
    # DBDish::mysql returns variable-length text columns (varchar/text/etc.)
    # as Buf rather than Str; decode at the boundary so downstream logic
    # below sees plain strings.
    $value = $value.decode('utf-8') if $value ~~ Blob;
    given $type {
      when /:i ^ [ bool | 'tinyint(1)' ] / {
        return $value if $value ~~ Bool;
        return $value.Int.Bool;
      }
      when /:i datetime | timestamp | ^ date | ^ time / {
        return $value if $value ~~ DateTime | Date;
        my $s = $value.Str;
        return $value unless $s;
        my $iso = $s.subst(' ', 'T');
        return DateTime.new($iso) if $iso ~~ /^ \d ** 4 '-' \d\d '-' \d\d 'T' \d\d ':' \d\d ':' \d\d /;
        return Date.new($s) if $s ~~ /^ \d ** 4 '-' \d\d '-' \d\d $/;
        $value;
      }
      when /:i ^ [ int | bigint | smallint | tinyint | mediumint | integer ] / {
        return $value if $value ~~ Int;
        return $value.Str.Int if $value.Str ~~ /^ '-'? \d+ $/;
        $value;
      }
      when /:i ^ [ decimal | numeric | float | double | real ] / {
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
      when /:i ^ [ bool | 'tinyint(1)' ] / {
        return $value.Int if $value ~~ Bool;
        return $value if $value ~~ Int;
        my $s = $value.Str.lc;
        return 1 if $s eq 'true' | 't' | '1' | 'y' | 'yes';
        return 0 if $s eq 'false' | 'f' | '0' | 'n' | 'no';
        $value;
      }
      when /:i datetime | timestamp | ^ date | ^ time / {
        if $value ~~ DateTime {
          my $local = $value.in-timezone($*TZ);
          my $iso = $local.Str;
          $iso ~~ s/'T'/ /;
          $iso ~~ s/<[+\-]> \d\d ':' \d\d $//;
          $iso ~~ s/'Z'$//;
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

    $stmt.sql = "INSERT INTO $table ($fields) VALUES ($values)";
    $stmt;
  }

  method create-object(Mu:D $obj) {
    my $table = Utils.table-name($obj);
    my %attrs = $obj.attrs;
    my %types = self!types-from-fields($obj);
    my $stmt  = self.build-insert(:$table, :%attrs, :%types);

    self.exec-stmt($stmt);
    self.exec('SELECT LAST_INSERT_ID()')[0][0].Int;
  }

  method !types-from-fields(Mu:D $obj) {
    my %types;
    for $obj.fields -> $f { %types{$f.name} = $f.type }
    %types;
  }

  method get-fields(Str:D :$table) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $tph = $stmt.placeholder($table);
    $stmt.sql = qq:to/SQL/;
      SELECT column_name, LOWER(data_type), LOWER(column_type)
        FROM information_schema.columns
       WHERE table_schema = DATABASE() AND table_name = $tph
       ORDER BY ordinal_position
      SQL
    my @out;
    for self.exec-stmt($stmt) -> $row {
      my $name      = self!stringify($row[0]);
      my $data-type = self!stringify($row[1]);
      my $col-type  = self!stringify($row[2]);
      @out.push: [$name, self!normalize-type($data-type, $col-type)];
    }
    @out;
  }

  # MySQL's information_schema reports types like 'int' and 'varchar'.
  # Translate them into the canonical names used by Model.init-attrs and
  # the rest of the adapter layer ('integer', 'character varying', etc.)
  # so MySQL-backed models speak the same vocabulary as the PG-backed ones.
  method !normalize-type(Str:D $data-type, Str:D $col-type --> Str) {
    return 'boolean' if $data-type eq 'tinyint' && $col-type eq 'tinyint(1)';
    given $data-type {
      when 'tinyint' | 'smallint' | 'mediumint' | 'int' | 'bigint' { 'integer' }
      when 'varchar' | 'char'                                      { 'character varying' }
      when 'text' | 'tinytext' | 'mediumtext' | 'longtext'         { 'text' }
      when 'decimal' | 'numeric'                                   { 'numeric' }
      when 'float' | 'double'                                      { 'double' }
      default                                                      { $data-type }
    }
  }

  method get-table-names {
    my $rows = self.exec(qq:to/SQL/);
      SELECT table_name FROM information_schema.tables
       WHERE table_schema = DATABASE()
       ORDER BY table_name
      SQL
      @$rows.map({ self!stringify($_[0]) });
    }

    method ddl-drop-all-tables(--> List) {
      my @tables = self.get-table-names.list;
      return @tables unless @tables.elems;
      self.exec('SET FOREIGN_KEY_CHECKS = 0');
      LEAVE self.exec('SET FOREIGN_KEY_CHECKS = 1');
      self.exec("DROP TABLE IF EXISTS `{$_}`") for @tables;
      @tables;
    }

    # DBDish::mysql returns information_schema text columns as Buf — decode
    # them once at the introspection boundary so consumers see plain Str.
    method !stringify($v --> Str) {
      return '' without $v;
      return $v.decode('utf-8') if $v ~~ Blob;
      $v.Str;
    }

    method delete-records(Str:D :$table, :%where, :%where-not) {
      my $stmt = SqlStmt.new(:adapter(self));
      my $where-sql = self.build-where($stmt, %where, %where-not);
      my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
      $stmt.sql = "DELETE FROM $table $where-clause";
      self.check-write-allowed($stmt.sql);
      self.connect unless self.db.defined;
      Log.sql(:sql($stmt.sql));
      my $query = self.db.prepare($stmt.sql);
      $query.execute(|$stmt.binds);
      $query.rows.Int;
    }

    method update-records(Str:D :$table, :%attrs, :%types = {}, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
      my $stmt = self.build-update-where(:$table, :%attrs, :%types, :%where, :%where-not, :@or-groups, :@locking-bump);
      self!run-write($stmt);
    }

    method update-counter-records(Str:D :$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump = () --> Int) {
      my $stmt = self.build-update-counters-where(:$table, :%counters, :%where, :%where-not, :@or-groups, :@locking-bump);
      self!run-write($stmt);
    }

    method insert-records(Str:D :$table, :@rows, :%types = {}, Bool:D :$skip-conflict = False --> List) {
      my $stmt = self.build-insert-many(:$table, :@rows, :%types);
      if $skip-conflict {
        $stmt.sql ~~ s/^'INSERT INTO'/INSERT IGNORE INTO/;
      }
      self.check-write-allowed($stmt.sql);
      self.connect unless self.db.defined;
      Log.sql(:sql($stmt.sql));
      my $query = self.db.prepare($stmt.sql);
      $query.execute(|$stmt.binds);
      my $affected = $query.rows.Int;
      return () unless $affected;
      my $first = self.exec('SELECT LAST_INSERT_ID()')[0][0].Int;
      ($first .. $first + $affected - 1).list;
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
      if @update.elems {
        my $set-list = @update.map({ "$_ = VALUES($_)" }).join(', ');
        $stmt.sql ~= " ON DUPLICATE KEY UPDATE $set-list";
      } else {
        my $first = @conflict-cols[0];
        $stmt.sql ~= " ON DUPLICATE KEY UPDATE $first = $first";
      }
      self!run-write($stmt);
    }

    method !run-write(SqlStmt:D $stmt --> Int) {
      self.check-write-allowed($stmt.sql);
      self.connect unless self.db.defined;
      Log.sql(:sql($stmt.sql));
      my $query = self.db.prepare($stmt.sql);
      $query.execute(|$stmt.binds);
      $query.rows.Int;
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

      my @parts;
      @parts.push(self!mysql-id-column(%pk<pk-name>, %pk<id-type>)) if %pk<emit-id-col>;
      @parts.append(@field-defs);
      @parts.append(@fk-clauses);
      @parts.push("PRIMARY KEY ({%pk<pk-cols>.join(', ')})") if %pk<want-pk>;

      my $body = @parts.join(",\n        ");
      my $comment-clause = $comment.defined ?? ' COMMENT=' ~ self!string-literal($comment.Str) !! '';
      self.exec(qq:to/SQL/);
      {$prefix}$table (
        $body
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4$comment-clause
      SQL
      }

      method !mysql-id-column(Str:D $name, Str:D $type --> Str) {
        given $type {
          when 'integer'         { "$name INT NOT NULL AUTO_INCREMENT" }
          when 'bigint'          { "$name BIGINT NOT NULL AUTO_INCREMENT" }
          when 'uuid'            { "$name CHAR(36) NOT NULL" }
          when 'string' | 'text' { "$name VARCHAR(255) NOT NULL" }
          default                { "$name " ~ self!sql-type-for($type) ~ ' NOT NULL' }
        }
      }

      method ddl-add-column(Str:D $table, Pair:D $param, Bool :$if-not-exists = False) {
        my $clause = $if-not-exists ?? self.ref-column-if-not-exists-clause !! '';
        for self.ddl-column-defs($param) -> $col {
          self.exec("ALTER TABLE $table ADD COLUMN {$clause}$col");
        }
      }

      method ddl-column-defs(Pair:D $param --> List) {
        my @fk-clauses;
        self!build-fields([$param], :@fk-clauses);
      }

      method ddl-change-column(Str:D $table, Str:D $name, Str:D $type, *%opts) {
        my $sql-type = self!sql-type-for($type, limit => %opts<limit>);
        my %info     = self!column-info($table, $name);

        my Bool $null = %opts<null>:exists ?? %opts<null>.so !! %info<null>;
        my $default-lit = %opts<default>:exists
          ?? (%opts<default>.defined ?? self!default-literal(%opts<default>) !! Nil)
          !! %info<default-literal>;
        my $comment   = %opts<comment>:exists ?? %opts<comment> !! %info<comment>;

        my $clause = self!modify-column-clause(
          $name, $sql-type,
          :$null,
          default => $default-lit,
          :$comment,
        );
        self.exec("ALTER TABLE $table MODIFY COLUMN $clause");
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

        my %info   = self!column-info($table, $name);
        my $clause = self!modify-column-clause(
          $name, %info<sql-type>,
          :$null,
          default => %info<default-literal>,
          comment => %info<comment>,
        );
        self.exec("ALTER TABLE $table MODIFY COLUMN $clause");
      }

      method ddl-change-column-comment(Str:D $table, Str:D $name, $comment) {
        my %info   = self!column-info($table, $name);
        my $clause = self!modify-column-clause(
          $name, %info<sql-type>,
          null    => %info<null>,
          default => %info<default-literal>,
          comment => ($comment.defined ?? $comment.Str !! ''),
        );
        self.exec("ALTER TABLE $table MODIFY COLUMN $clause");
      }

      method ddl-change-table-comment(Str:D $table, $comment) {
        my $literal = $comment.defined
          ?? self!string-literal($comment.Str)
          !! "''";
        self.exec("ALTER TABLE $table COMMENT = $literal");
      }

      method !modify-column-clause(Str:D $name, Str:D $sql-type, Bool :$null, :$default, :$comment --> Str) {
        my $null-clause    = $null.defined ?? ($null ?? ' NULL' !! ' NOT NULL') !! '';
        my $default-clause = $default.defined && $default.Str.chars
          ?? " DEFAULT $default"
          !! '';
        my $comment-clause = $comment.defined && $comment.Str.chars
          ?? ' COMMENT ' ~ self!string-literal($comment.Str)
          !! '';

        "$name $sql-type$null-clause$default-clause$comment-clause";
      }

      method !column-info(Str:D $table, Str:D $name --> Hash) {
        my $stmt = SqlStmt.new(:adapter(self));
        my $tph  = $stmt.placeholder($table);
        my $nph  = $stmt.placeholder($name);
        $stmt.sql = qq:to/SQL/;
          SELECT column_type, is_nullable, column_default, column_comment
            FROM information_schema.columns
           WHERE table_schema = DATABASE()
             AND table_name = $tph
             AND column_name = $nph
          SQL

        my @rows = self.exec-stmt($stmt);
        die "MySqlAdapter: no such column $table.$name" unless @rows.elems;

        my $row    = @rows[0];
        my $type   = self!stringify($row[0]);
        my $is-nul = self!stringify($row[1]);
        my $dflt   = $row[2].defined ?? self!stringify($row[2]) !! Nil;
        my $cmt    = self!stringify($row[3]);

        %( sql-type        => $type,
           null            => ($is-nul.uc eq 'YES'),
           default-literal => ($dflt.defined && $dflt.chars ?? self!quote-mysql-default($dflt) !! Nil),
           comment         => $cmt );
      }

      # MySQL's information_schema returns column_default as a raw expression
      # (e.g. CURRENT_TIMESTAMP) or as a bare literal (no surrounding quotes
      # for strings). Heuristic: numeric / NULL / CURRENT_* pass through, the
      # rest are treated as string literals and re-quoted.
      method !quote-mysql-default(Str:D $raw --> Str) {
        return $raw if $raw ~~ /^ '-'? \d+ ('.' \d+)? $/;
        return $raw if $raw.uc eq 'NULL';
        return $raw if $raw.uc.starts-with('CURRENT_');
        self!string-literal($raw);
      }

      method !sql-type-for(Str:D $type, :$limit) {
        given $type {
          when 'string'                 { 'VARCHAR(' ~ ($limit // 255) ~ ')' }
          when 'text'                   { 'TEXT' }
          when 'integer'                { 'INT' }
          when 'bigint'                 { 'BIGINT' }
          when 'smallint'               { 'SMALLINT' }
          when 'boolean'                { 'TINYINT(1)' }
          when 'decimal' | 'numeric'    { 'DECIMAL' }
          when 'float'                  { 'DOUBLE' }
          when 'money'                  { 'DECIMAL(19, 4)' }
          when 'datetime' | 'timestamp' | 'timestamptz' { 'DATETIME(6)' }
          when 'date'                   { 'DATE' }
          when 'time'                   { 'TIME' }
          when 'uuid'                   { 'CHAR(36)' }
          when 'binary'                 { $limit ?? "VARBINARY($limit)" !! 'BLOB' }
          when 'json' | 'jsonb'         { 'JSON' }
          default                       { $type.uc }
        }
      }

      method !default-literal($value --> Str) {
        return 'NULL' without $value;
        return $value().Str if $value ~~ Callable;
        return ($value ?? '1' !! '0') if $value ~~ Bool;
        return $value.Str if $value ~~ Numeric;
        self!string-literal($value.Str);
      }

      method !string-literal(Str:D $s --> Str) {
        "'" ~ $s.subst("\\", "\\\\", :g).subst("'", "''", :g) ~ "'";
      }

      # ---- JSON operators (MySQL) ----
      # Path extraction (`->> '$.a.b'`) uses the shared default in SqlBuilders.

      method json-contains-sql(SqlStmt:D $stmt, Str:D $col, $data --> Str) {
        "JSON_CONTAINS($col, " ~ $stmt.placeholder(self.json-literal($data)) ~ ')';
      }

      method json-has-key-sql(SqlStmt:D $stmt, Str:D $col, Str:D $key --> Str) {
        "JSON_CONTAINS_PATH($col, 'one', " ~ $stmt.placeholder('$.' ~ $key) ~ ')';
      }

      method ddl-add-timestamps(Str:D $table) {
        self.exec(qq:to/SQL/);
      ALTER TABLE $table
       ADD COLUMN created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
       ADD COLUMN updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
      SQL
        }

        method ddl-rename-index(Str:D $table, Str:D $from, Str:D $to) {
          self.exec("ALTER TABLE $table RENAME INDEX $from TO $to");
        }

        # MySQL carries the access method as an index_option after the column
        # list, wraps functional indexes in an extra set of parentheses, and
        # requires the table name to drop an index. Partial (WHERE) indexes,
        # covering INCLUDE, CONCURRENTLY, and operator classes are unsupported.
        method ref-index-using-prefix(Str:D $using --> Str) { '' }
        method ref-index-using-suffix(Str:D $using --> Str) { " USING {$using.uc}" }
        method ref-index-expression-body(Str:D $expression --> Str) { "($expression)" }
        method ref-index-supports-opclass(--> Bool) { False }

        method ref-index-algorithm-keyword($algorithm --> Str) {
          return '' without $algorithm;
          die 'MySqlAdapter: index algorithm (e.g. CONCURRENTLY) is not supported';
        }

        method ref-index-where-clause(Str:D $where --> Str) {
          die 'MySqlAdapter: partial (WHERE) indexes are not supported';
        }

        method ref-index-include-clause($include --> Str) {
          die 'MySqlAdapter: covering index INCLUDE is not supported';
        }

        method ddl-remove-index(Str:D :$name, Str :$table, :$algorithm, Bool :$if-exists = False) {
          self.ref-index-algorithm-keyword($algorithm);
          self.ref-index-if-exists-clause if $if-exists;

          $table.defined
            ?? self.exec("ALTER TABLE $table DROP INDEX $name")
            !! self.exec("DROP INDEX $name");
        }

        method ref-index-if-not-exists-clause(--> Str) {
          die 'MySqlAdapter: CREATE INDEX IF NOT EXISTS is not supported';
        }
        method ref-index-if-exists-clause(--> Str) {
          die 'MySqlAdapter: DROP INDEX IF EXISTS is not supported';
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
          self.exec("ALTER TABLE $from-table DROP FOREIGN KEY $fkname");
        }

        method ref-check-not-valid-suffix(--> Str) { ' NOT ENFORCED' }

        method ddl-remove-check-constraint(Str:D $table,
                                           Str :$expression,
                                           Str :$name) {
          my $cname = $name // do {
            die 'remove-check-constraint: pass :name or :expression' unless $expression.defined;
            self.ref-default-check-name($table, $expression);
          };
          self.exec("ALTER TABLE $table DROP CHECK $cname");
        }

        method ddl-validate-check-constraint(Str:D $table, Str:D $name) {
          self.exec("ALTER TABLE $table ALTER CHECK $name ENFORCED");
        }

        method ddl-remove-unique-constraint(Str:D $table,
                                            :$columns,
                                            Str :$name) {
          my @cols = self.ref-columns-list($columns);
          my $cname = $name // do {
            die 'remove-unique-constraint: pass :name or :columns' unless @cols.elems;
            self.ref-default-unique-name($table, @cols);
          };
          self.exec("ALTER TABLE $table DROP INDEX $cname");
        }

        method !build-fields(@params, :@fk-clauses) {
          my @fields;

          for @params {
            my $name = $_.keys.first;
            my $field_name = $name ~~ Pair ?? $name.keys.first !! $name;

            my Bool $is-reference   = $_{$name}<reference>:exists;
            my Bool $is-polymorphic = ($_{$name}<polymorphic>:exists) && $_{$name}<polymorphic>.so;

            if $is-reference && $is-polymorphic {
              @fields.push($field_name ~ '_id INT');
              @fields.push($field_name ~ '_type VARCHAR(255)');
              next;
            }

            my $type  = '';
            my $limit = '';
            my $limit-val;
            my $null  = '';
            my Bool $is-bool = False;
            my Bool $has-default = False;
            my $default-value;
            my $charset;
            my $collation;
            my $generated-as;
            my Bool $stored = False;
            my $comment;
            my Bool $is-decimal = False;
            my Bool $is-binary = False;
            my Bool $is-money = False;
            my $precision;
            my $scale;

            for $_{$name}.keys -> $attr {
              my $value = $_{$name}{$attr};

              given $attr {
                when 'string'    { $type = 'VARCHAR' }
                when 'text'      { $type = 'TEXT' }
                when 'integer'   { $type = 'INT' }
                when 'bigint'    { $type = 'BIGINT' }
                when 'smallint'  { $type = 'SMALLINT' }
                when 'boolean'   { $type = 'TINYINT'; $is-bool = True }
                when 'decimal' | 'numeric' { $type = 'DECIMAL'; $is-decimal = True }
                when 'float'     { $type = 'DOUBLE' }
                when 'money'     { $type = 'DECIMAL'; $is-decimal = True; $is-money = True }
                when 'datetime' | 'timestamp' { $type = 'DATETIME(6)' }
                when 'timestamptz' { $type = 'DATETIME(6)' }
                when 'date'      { $type = 'DATE' }
                when 'time'      { $type = 'TIME' }
                when 'interval'  { die 'MySqlAdapter: :interval columns are PostgreSQL-only' }
                when 'uuid'      { $type = 'CHAR(36)' }
                when 'binary'    { $is-binary = True }
                when 'json'      { $type = 'JSON' }
                when 'jsonb'     { $type = 'JSON' }
                when 'hstore'    { die 'MySqlAdapter: :hstore columns are PostgreSQL-only' }
                when 'xml'       { die 'MySqlAdapter: :xml columns are PostgreSQL-only' }
                when 'array' | 'ltree' | 'inet' | 'cidr' | 'macaddr'
                   | 'int4range' | 'int8range' | 'numrange' | 'tsrange' | 'tstzrange' | 'daterange'
                   | 'point' | 'line' | 'lseg' | 'box' | 'path' | 'polygon' | 'circle' {
                  die "MySqlAdapter: :$attr columns are PostgreSQL-only";
                }
                when 'limit'     { $limit-val = $value; $limit = '(' ~ $value ~ ')' }
                when 'precision' { $precision = $value }
                when 'scale'     { $scale = $value }
                when 'default'   { $has-default = True; $default-value = $value }
                when 'null'      { $null = $value }
                when 'charset'   { $charset = $value }
                when 'collation' { $collation = $value }
                when 'as'        { $generated-as = $value }
                when 'stored'    { $stored = $value.so }
                when 'virtual'   { }
                when 'comment'   { $comment = $value }
                when 'reference' {
                  $type = 'INT';
                  $field_name = $field_name ~ '_id';
                  @fk-clauses.push("FOREIGN KEY ($field_name) REFERENCES { $name ~ 's' }(id)");
                }
                default { die 'MySqlAdapter: unknown column attr: ' ~ $attr }
              }
            }

            given $type {
              when 'VARCHAR' { $limit = '(255)' unless $limit }
              when 'TINYINT' { $limit = '(1)' if $is-bool }
              default        { $limit = '' if $type ne 'VARCHAR' && $type ne 'TINYINT' }
            }

            if $is-binary {
              $type  = $limit-val.defined ?? 'VARBINARY' !! 'BLOB';
              $limit = $limit-val.defined ?? "($limit-val)" !! '';
            }
            elsif $is-decimal {
              my $p = $precision // ($is-money ?? 19 !! Nil);
              my $s = $scale     // ($is-money ?? 4  !! Nil);
              $limit = $p.defined ?? "($p" ~ ($s.defined ?? ", $s" !! '') ~ ')' !! '';
            }

            my $col = "$field_name $type$limit";

            $col ~= ' CHARACTER SET ' ~ $charset if $charset.defined;
            $col ~= ' COLLATE ' ~ $collation     if $collation.defined;

            if $generated-as.defined {
              my $kind = $stored ?? 'STORED' !! 'VIRTUAL';
              $col ~= " GENERATED ALWAYS AS ($generated-as) $kind";
            }
            elsif $has-default {
              $col ~= ' DEFAULT ' ~ self!default-literal($default-value);
            }

            $col ~= self.ref-null-clause($null);

            $col ~= ' COMMENT ' ~ self!string-literal($comment.Str) if $comment.defined;

            @fields.push($col);
          }

          @fields;
        }
      }
