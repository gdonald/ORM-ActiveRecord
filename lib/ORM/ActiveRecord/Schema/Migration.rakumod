
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

class Migration is export {
  has DB $!db;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD {
    $!db = DB.shared;
  }

  method create-table(Str:D $table, @params) {
    $!db.ddl-create-table($table, @params);
  }

  method drop-table(Str:D $table) {
    $!db.ddl-drop-table($table);
  }

  method add-column(Str:D $table, Pair:D $params) {
    $!db.ddl-add-column($table, $params);
  }

  method remove-column(Str:D $table, |params) {
    my $field = params.keys.first;
    $!db.ddl-remove-column($table, $field);
  }

  method add-timestamps(Str:D $table) {
    $!db.ddl-add-timestamps($table);
  }

  method remove-timestamps(Str:D $table) {
    $!db.ddl-remove-timestamps($table);
  }

  method add-index(Str:D $table, |params) {
    my $params = params;
    my $field = params.keys.first;
    my $name = $table ~ '_' ~ $field ~ '_idx';
    my Bool $unique = False;

    if !params{$field} {
      my ($keys, $values) = params[0].kv;

      if $keys ~~ List {
        $params = $values;
        $name = $table ~ '_' ~ $keys.join('_') ~ '_idx';
        $field = $keys.join(', ');
      }
    }

    for $params -> $param {
      given $param {
        when /:i unique/ { $unique = True }
        when .so {}
        default { say 'Unknown index param: ' ~ $param; die }
      }
    }

    $!db.ddl-add-index($table, :$name, columns => $field, :$unique);
  }

  method remove-index(Str:D $table, |params) {
    my $field = params.keys.first;
    my $name = $table ~ '_' ~ $field ~ '_idx';
    $!db.ddl-remove-index(:$name);
  }

  method irreversible-migration {
    die X::IrreversibleMigration.new;
  }
}
