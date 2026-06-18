
use MONKEY-SEE-NO-EVAL;
use YAMLish;

use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Utils;

# Loads YAML fixtures into the database. Each top-level key in a fixture file is
# a label; its id is derived deterministically from the label (so references
# resolve across files without ordering), unless an explicit `id` is given.
#
#   # users.yml
#   alice:
#     name: Alice
#     admin: <%= True %>
#   # articles.yml
#   hello:
#     title: Hello
#     author: alice            # belongs-to: author_id = identify('alice')
#
#   my $fx = Fixtures.new(dir => 'test/fixtures').load;
#   $fx.id('users', 'alice');          # the deterministic id
#   $fx.record('articles', 'hello');   # the inserted row hash
class Fixtures is export {
  has $.dir;
  has %.loaded;

  # Stable label → integer id, the Raku equivalent of Rails' FixtureSet.identify.
  method identify(Str:D $label --> Int) {
    Utils.fnv1a-hex($label).substr(0, 8).parse-base(16) % 1_000_000_000 + 1;
  }

  method !adapter { DB.shared.adapter }

  # ERB-equivalent interpolation: <%= expr %> is replaced by the stringified
  # value of the Raku expression before the YAML is parsed.
  method !interpolate(Str:D $text --> Str) {
    $text.subst(/ '<%=' \s* $<expr>=[<-[%]>+] '%>' /, -> $m { (EVAL ~$m<expr>).Str }, :g);
  }

  method !columns(Str:D $table) {
    self!adapter.get-fields(:$table).map({ .[0] }).Set;
  }

  method !types(Str:D $table) {
    my %types;
    %types{.[0]} = .[1] for self!adapter.get-fields(:$table);
    %types;
  }

  method load-file(Str:D $path, Str :$table is copy) {
    $table //= $path.IO.basename.subst(/ '.' \w+ $ /, '');

    my %data    = load-yaml(self!interpolate($path.IO.slurp));
    my %columns = self!columns($table);
    my %types   = self!types($table);

    my @rows;
    my %by-label;

    for %data.kv -> $label, %attrs {
      my %row = id => (%attrs<id> // self.identify($label));

      for %attrs.kv -> $key, $value {
        next if $key eq 'id';

        if %columns{$key} {
          %row{$key} = $value;
        } elsif %columns{$key ~ '_id'} {
          # belongs-to reference: the value names another fixture's label.
          %row{$key ~ '_id'} = self.identify(~$value);
        }
      }

      @rows.push: %row;
      %by-label{$label} = %row;
    }

    try self!adapter.exec("DELETE FROM $table");

    if @rows.elems {
      my $stmt = self!adapter.build-insert-many(:$table, :@rows, :%types, :include-id);
      self!adapter.exec-stmt($stmt);
    }

    %!loaded{$table} = %by-label;
    %by-label;
  }

  method load(:@files, :$dir is copy) {
    $dir //= $!dir;

    my @paths = @files.elems
      ?? @files.map({ $dir.defined ?? $dir.IO.add($_).Str !! $_ })
      !! $dir.IO.dir.grep({ .extension eq 'yml' | 'yaml' }).map(*.Str).sort;

    self.load-file($_) for @paths;
    self;
  }

  method record(Str:D $table, Str:D $label) {
    %!loaded{$table}{$label};
  }

  method id(Str:D $table, Str:D $label) {
    (%!loaded{$table}{$label} // {})<id>;
  }

  method labels(Str:D $table) {
    (%!loaded{$table} // {}).keys.sort.list;
  }
}
