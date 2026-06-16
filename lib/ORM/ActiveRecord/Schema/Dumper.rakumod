
# Renders a portable `db/schema.raku` (a Migration subclass that recreates the
# tables) from live introspection. Column types are mapped back to the logical
# adverbs; limits, defaults, and foreign keys are not recoverable through the
# introspection API and are omitted (use `db:structure:dump` for an exact,
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

  method !column-block(@columns --> Str) {
    return '' unless @columns.elems;
    my $width = @columns.map(*.<name>.chars).max;
    @columns.map(-> %col {
      my $pad = ' ' x ($width - %col<name>.chars);
      '      ' ~ %col<name> ~ $pad ~ ' => { :' ~ %col<adverb> ~ ' },'
    }).join("\n");
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

  method !create-table-block(Str:D $table --> Str) {
    my @columns = self!columns($table);
    my $has-id  = @columns.first({ .<name> eq 'id' }).defined;
    my @listed  = @columns.grep({ .<name> ne 'id' });

    my $columns = self!column-block(@listed);
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
