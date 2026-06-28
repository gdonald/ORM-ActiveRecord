
# Renders a portable `db/schema.raku` (a Migration subclass that recreates the
# tables) from live introspection. Column types are mapped back to the logical
# adverbs. Foreign keys are introspected and emitted as add-foreign-key calls
# after every table is created. Limits and defaults are not recoverable through
# the introspection API and are omitted (use `db:structure:dump` for an exact,
# database-specific dump).

class SchemaDumper is export {
  has $.adapter;
  has @.versions = ();

  my %TYPE-MAP =
    'character varying'           => 'string',
    'varchar'                     => 'string',
    'char'                        => 'string',
    'text'                        => 'text',
    'integer'                     => 'integer',
    'int'                         => 'integer',
    'bigint'                      => 'bigint',
    'smallint'                    => 'smallint',
    'boolean'                     => 'boolean',
    'numeric'                     => 'decimal',
    'decimal'                     => 'decimal',
    'double precision'            => 'float',
    'double'                      => 'float',
    'real'                        => 'float',
    'float'                       => 'float',
    'money'                       => 'money',
    'timestamp with time zone'    => 'datetime',
    'timestamp without time zone' => 'datetime',
    'timestamp'                   => 'datetime',
    'datetime'                    => 'datetime',
    'date'                        => 'date',
    'time without time zone'      => 'time',
    'time'                        => 'time',
    'uuid'                        => 'uuid',
    'bytea'                       => 'binary',
    'blob'                        => 'binary',
    'binary'                      => 'binary',
    'varbinary'                   => 'binary',
    'json'                        => 'json',
    'jsonb'                       => 'jsonb',
  ;

  method !adverb-for(Str:D $type --> Str) {
    %TYPE-MAP{$type.lc} // $type.lc;
  }

  method tables {
    $!adapter.get-table-names.list.grep({ $_ ne 'migrations' }).sort;
  }

  method !columns(Str:D $table) {
    $!adapter.get-fields(:$table).map({ %( name => .[0], adverb => self!adverb-for(~.[1]) ) }).list;
  }

  method !indexes(Str:D $table) {
    $!adapter.get-indexes(:$table).grep({
      .<name> !~~ / '_pkey' $ / && .<name> !~~ /^ 'sqlite_autoindex' /
    }).list;
  }

  method !foreign-keys(Str:D $table) {
    $!adapter.get-foreign-keys(:$table).list;
  }

  method !column-block(Str:D $table, @columns, %fk-by-column --> Str) {
    return '' unless @columns.elems;
    my $width = @columns.map(*.<name>.chars).max;
    @columns.map(-> %col {
      my $pad = ' ' x ($width - %col<name>.chars);
      my $suffix = %fk-by-column{%col<name>}:exists
        ?? self!inline-fk-suffix($table, %fk-by-column{%col<name>})
        !! '';
      '      ' ~ %col<name> ~ $pad ~ ' => { :' ~ %col<adverb> ~ $suffix ~ ' },'
    }).join("\n");
  }

  # SQLite can't ALTER in a foreign key, so its dump declares the FK inline on
  # the column with a `references` adverb instead of a trailing add-foreign-key.
  method !inline-fk-suffix(Str:D $from-table, %fk --> Str) {
    my @opts = "references => '%fk<to-table>'";

    @opts.push: "fk-primary-key => '%fk<primary-key>'"
      if %fk<primary-key>.defined && %fk<primary-key> ne 'id';

    my $default-name = $!adapter.ref-default-fk-name($from-table, %fk<column>);
    @opts.push: "fk-name => '%fk<name>'"
      if %fk<name>.defined && %fk<name> ne $default-name;

    @opts.push: "on-delete => '%fk<on-delete>'" if %fk<on-delete>.defined;
    @opts.push: "on-update => '%fk<on-update>'" if %fk<on-update>.defined;

    ', ' ~ @opts.join(', ');
  }

  method !index-line(Str:D $table, %index --> Str) {
    my @cols = %index<columns>.list;

    # Positional column form: a named `:colname` would clash with add-index's
    # own option names (e.g. a column literally called `name`).
    my $columns = @cols.elems == 1
      ?? "'" ~ @cols[0] ~ "'"
      !! '<' ~ @cols.join(' ') ~ '>';

    my $unique = %index<unique> ?? ', :unique' !! '';

    "    self.add-index: '$table', $columns$unique;";
  }

  method !foreign-key-line(Str:D $from-table, %fk --> Str) {
    my @parts = "'$from-table'", "'%fk<to-table>'";

    @parts.push: "column => '%fk<column>'"
      if %fk<column> ne $!adapter.ref-default-column(%fk<to-table>);

    @parts.push: "primary-key => '%fk<primary-key>'"
      if %fk<primary-key>.defined && %fk<primary-key> ne 'id';

    my $default-name = $!adapter.ref-default-fk-name($from-table, %fk<column>);
    @parts.push: "name => '%fk<name>'"
      if %fk<name>.defined && %fk<name> ne $default-name;

    @parts.push: "on-delete => '%fk<on-delete>'" if %fk<on-delete>.defined;
    @parts.push: "on-update => '%fk<on-update>'" if %fk<on-update>.defined;

    '    self.add-foreign-key: ' ~ @parts.join(', ') ~ ';';
  }

  method !create-table-block(Str:D $table --> Str) {
    my @columns = self!columns($table);
    my $has-id  = @columns.first({ .<name> eq 'id' }).defined;
    my @listed  = @columns.grep({ .<name> ne 'id' });

    my %fk-by-column;
    unless $!adapter.ref-supports-alter-foreign-key {
      for self!foreign-keys($table) -> %fk {
        %fk-by-column{%fk<column>} = %fk;
      }
    }

    my $columns = self!column-block($table, @listed, %fk-by-column);
    my $id-opt  = $has-id ?? '' !! ', :id(False)';

    my $block = "    self.create-table: '$table', [\n";
    $block ~= "$columns\n" if $columns;
    $block ~= "    ]$id-opt;";

    for self!indexes($table) -> %index {
      $block ~= "\n" ~ self!index-line($table, %index);
    }

    $block;
  }

  method render-schema(--> Str) {
    my @tables = self.tables;

    my $up = @tables.map({ self!create-table-block($_) }).join("\n\n");
    $up = '' unless @tables.elems;

    # On adapters that support ALTER TABLE ADD FOREIGN KEY, emit the constraints
    # after every create-table so a target table always exists by the time its
    # constraint is added. SQLite declares them inline on the column instead.
    my @fk-lines;
    if $!adapter.ref-supports-alter-foreign-key {
      for @tables -> $table {
        for self!foreign-keys($table) -> %fk {
          @fk-lines.push: self!foreign-key-line($table, %fk);
        }
      }
    }
    $up ~= "\n\n" ~ @fk-lines.join("\n") if @fk-lines.elems;

    my $down = @tables.reverse.map({ "    self.drop-table: '$_';" }).join("\n");

    my $versions = @!versions.elems
      ?? '<' ~ @!versions.sort.join(' ') ~ '>'
      !! '()';

    qq:to/RAKU/;

    use ORM::ActiveRecord::Schema::Migration;

    class Schema is Migration \{
      method up \{
    $up
      \}

      method down \{
    $down
      \}

      method versions \{ $versions \}
    \}
    RAKU
  }
}
