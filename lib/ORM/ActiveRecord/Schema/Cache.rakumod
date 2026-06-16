
use JSON::Tiny;
use YAMLish;
use ORM::ActiveRecord::DB;

# A snapshot of the database schema (tables → columns / indexes / constraints,
# plus sequences) that can be dumped to JSON and loaded back, so an app can
# skip live introspection on boot.
class SchemaCache is export {
  has $.adapter is rw;
  has %.data;

  method !adapter {
    $!adapter //= DB.shared.adapter;
  }

  method build {
    my $adapter = self!adapter;
    my %tables;

    for $adapter.get-table-names.list -> $table {
      %tables{$table} = %(
        columns     => $adapter.get-fields(:$table).map({ %( name => .[0], type => .[1] ) }).list,
        indexes     => $adapter.get-indexes(:$table),
        constraints => $adapter.get-constraints(:$table),
      );
    }

    %!data = %( tables => %tables, sequences => $adapter.get-sequences.list );
    self;
  }

  method serialize(--> Str) {
    self.build unless %!data;
    to-json(%!data);
  }

  method dump(Str:D :$path --> Str) {
    my $json = self.serialize;
    $path.IO.spurt($json);
    $json;
  }

  method deserialize(Str:D $json) {
    %!data = from-json($json);
    self;
  }

  method load(Str:D :$path) {
    self.deserialize($path.IO.slurp);
  }

  method serialize-yaml(--> Str) {
    self.build unless %!data;
    save-yaml(%!data);
  }

  method dump-yaml(Str:D :$path --> Str) {
    my $yaml = self.serialize-yaml;
    $path.IO.spurt($yaml);
    $yaml;
  }

  method deserialize-yaml(Str:D $yaml) {
    %!data = load-yaml($yaml);
    self;
  }

  method load-yaml(Str:D :$path) {
    self.deserialize-yaml($path.IO.slurp);
  }

  method table-names {
    (%!data<tables> // %()).keys.sort.list;
  }

  method columns-for(Str:D $table) {
    (%!data<tables>{$table}<columns> // []).list;
  }

  method indexes-for(Str:D $table) {
    (%!data<tables>{$table}<indexes> // []).list;
  }

  method constraints-for(Str:D $table) {
    (%!data<tables>{$table}<constraints> // []).list;
  }

  method sequences {
    (%!data<sequences> // []).list;
  }
}
