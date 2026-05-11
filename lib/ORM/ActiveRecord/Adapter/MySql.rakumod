
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
      self.connect unless self.db.defined;
      Log.sql(:sql($stmt.sql));
      my $query = self.db.prepare($stmt.sql);
      $query.execute(|$stmt.binds);
      $query.rows.Int;
    }

    # ---- DDL emission ----

    method ddl-create-table(Str:D $table, @params) {
      my @fk-clauses;
      my $fields = self!build-fields(@params, :@fk-clauses);
      my $fk-sql = @fk-clauses.elems ?? ', ' ~ @fk-clauses.join(', ') !! '';
      self.exec(qq:to/SQL/);
      CREATE TABLE $table (
        id INT NOT NULL AUTO_INCREMENT,
        $fields$fk-sql,
        PRIMARY KEY (id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
      SQL
      }

      method ddl-add-column(Str:D $table, Pair:D $param) {
        my @fk-clauses;
        my $fields = self!build-fields([$param], :@fk-clauses);
        self.exec("ALTER TABLE $table ADD COLUMN $fields");
      }

      method ddl-add-timestamps(Str:D $table) {
        self.exec(qq:to/SQL/);
      ALTER TABLE $table
       ADD COLUMN created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
       ADD COLUMN updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
      SQL
        }

        method !build-fields(@params, :@fk-clauses) {
          my @fields;

          for @params {
            my $name = $_.keys.first;
            my $field_name = $name ~~ Pair ?? $name.keys.first !! $name;

            my $type    = '';
            my $limit   = '';
            my $default = '';
            my $null    = '';
            my Bool $is-bool = False;

            for $_{$name}.keys -> $attr {
              my $value = $_{$name}{$attr};

              given $attr {
                when 'string'    { $type = 'VARCHAR' }
                when 'text'      { $type = 'TEXT' }
                when 'integer'   { $type = 'INT' }
                when 'boolean'   { $type = 'TINYINT'; $is-bool = True }
                when 'datetime' | 'timestamp' { $type = 'DATETIME(6)' }
                when 'limit'     { $limit = '(' ~ $value ~ ')' }
                when 'default'   { $default = $value }
                when 'null'      { $null = $value }
                when 'reference' {
                  $type = 'INT';
                  $field_name = $field_name ~ '_id';
                  @fk-clauses.push("FOREIGN KEY ($field_name) REFERENCES { $name ~ 's' }(id)");
                }
                default { say 'unknown attr: ' ~ $attr ~ ' ' ~ $value; die }
              }
            }

            given $type {
              when 'VARCHAR' { $limit = '(255)' unless $limit }
              when 'TINYINT' { $limit = '(1)' if $is-bool }
              default        { $limit = '' if $type ne 'VARCHAR' && $type ne 'TINYINT' }
            }

            if $is-bool && $default ne '' {
              given $default {
                when 'True'  { $default = ' DEFAULT 1' }
                when 'False' { $default = ' DEFAULT 0' }
                default      { $default = '' }
              }
            } elsif $type eq 'INT' && $default ne '' {
              $default = $default ~~ /^ '-'? \d+ $/
              ?? " DEFAULT $default"
              !! '';
            } else {
              $default = '';
            }

            given $null {
              when 'True'  { $null = ' NULL' }
              when 'False' { $null = ' NOT NULL' }
              default      { $null = '' }
            }

            @fields.push($field_name ~ ' ' ~ $type ~ $limit ~ $default ~ $null);
          }

          @fields.join(', ').trim;
        }
      }
