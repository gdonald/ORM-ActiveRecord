
class SqlStmt { ... }

role Adapter is export {
  # Connection lifecycle — engine-specific
  method connect()              { ... }
  method is-connected(--> Bool) { ... }
  method disconnect(--> Bool)   { ... }
  method reconnect()            { ... }
  method is-active(--> Bool)    { ... }
  method verify(--> Bool)       { ... }

  # Statement execution — engine-specific (uses driver handle)
  method exec(Str:D $sql, *@binds)  { ... }
  method exec-stmt(SqlStmt:D $stmt) { ... }

  method explain(SqlStmt:D $stmt --> Str) { ... }

  # Bind placeholder syntax: '$N' (PG) vs '?' (SQLite, MySQL)
  method bind-placeholder(Int:D $n --> Str) { ... }

  # Transaction stack — block helper with savepoints for nested calls
  method transaction(&block, Bool :$requires-new, Str :$isolation) { ... }
  method is-in-transaction(--> Bool) { ... }
  method register-txn-callback(Mu:D $record, Str:D $kind) { ... }

  # Schema introspection — varies (information_schema vs pragma_table_info)
  method get-fields(Str:D :$table)  { ... }
  method get-table-names()          { ... }

  # Catalog introspection beyond columns: indexes, constraints, sequences.
  # Each returns a List of Hashes (sequences: a List of names).
  method get-indexes(Str:D :$table --> List)     { ... }
  method get-constraints(Str:D :$table --> List) { ... }
  method get-sequences(--> List)                 { ... }

  # CRUD primitives whose SQL shape varies by dialect
  method build-insert(Str:D :$table, :%attrs, :%types --> SqlStmt) { ... }
  method delete-records(Str:D :$table, :%where, :%where-not --> Int) { ... }

  # Type coercion across the read/write boundary. Defaults pass through;
  # adapters override per dialect (e.g. SQLite stores Bool as INTEGER 0/1
  # and DATETIME as ISO TEXT, MySQL uses TINYINT(1) for Bool).
  method coerce-read($value, Str :$type)  { $value }
  method coerce-write($value, Str :$type) { $value }

  # SQL fragment for equality with explicit case-sensitivity. Default is
  # case-sensitive `=`, which already matches PG and SQLite. MySQL overrides
  # the case-sensitive branch to `BINARY col = ?` because its default
  # `_ci` collation otherwise compares case-insensitively.
  method case-eq-sql(Str:D $col, Bool:D :$case-sensitive --> Str) {
    $case-sensitive ?? "$col = ?" !! "LOWER($col) = LOWER(?)";
  }
}

class SqlStmt is export {
  has Adapter:D $.adapter is required;
  has Str  $.sql is rw = '';
  has      @.binds is rw;

  method placeholder($value --> Str) {
    @!binds.push($value);
    $!adapter.bind-placeholder(@!binds.elems);
  }

  method !walk(Str:D $template, &on-placeholder, &on-named --> Str) {
    my $out = '';
    my $i = 0;
    my $len = $template.chars;
    while $i < $len {
      my $c = $template.substr($i, 1);
      if $c eq "'" {
        $out ~= $c;
        $i++;
        while $i < $len {
          my $cc = $template.substr($i, 1);
          $out ~= $cc;
          $i++;
          if $cc eq "'" {
            if $i < $len && $template.substr($i, 1) eq "'" {
              $out ~= "'";
              $i++;
            } else {
              last;
            }
          }
        }
      } elsif $c eq '?' {
        $out ~= on-placeholder();
        $i++;
      } elsif $c eq ':'
            && $i + 1 < $len
            && $template.substr($i + 1, 1) ~~ /<[A..Za..z_]>/ {
        my $j = $i + 1;
        while $j < $len && $template.substr($j, 1) ~~ /<[A..Za..z0..9_]>/ {
          $j++;
        }
        my $name = $template.substr($i + 1, $j - $i - 1);
        $out ~= on-named($name);
        $i = $j;
      } else {
        $out ~= $c;
        $i++;
      }
    }
    $out;
  }

  method interpolate(Str:D $template, *@binds --> Str) {
    my $i = 0;
    my $out = self!walk(
      $template,
      {
        die "interpolate: too few binds for '?' placeholders" if $i >= @binds.elems;
        self.placeholder(@binds[$i++]);
      },
      -> $name { die "interpolate: ':$name' is not allowed with positional binds" },
    );
    die "interpolate: too many binds (used $i, given " ~ @binds.elems ~ ')'
      if $i < @binds.elems;
    $out;
  }

  method sanitize-array(@parts --> SqlStmt) {
    die 'sanitize-sql-array requires at least the SQL template' unless @parts.elems;
    my $template = @parts[0];
    my @args = @parts[1..*];

    if @args.elems == 1 && @args[0] ~~ Hash {
      my %named = @args[0];
      $!sql ~= self!walk(
        $template,
        { die "sanitize-sql-array: '?' placeholder is not allowed with named binds" },
        -> $name {
          die "sanitize-sql-array: missing bind for ':$name'" unless %named{$name}:exists;
          self.placeholder(%named{$name});
        },
      );
    } else {
      my $i = 0;
      $!sql ~= self!walk(
        $template,
        {
          die "sanitize-sql-array: too few binds for '?' placeholders" if $i >= @args.elems;
          self.placeholder(@args[$i++]);
        },
        -> $name { die "sanitize-sql-array: ':$name' is not allowed with positional binds" },
      );
      die "sanitize-sql-array: too many binds (used $i, given " ~ @args.elems ~ ')'
        if $i < @args.elems;
    }
    self;
  }
}
