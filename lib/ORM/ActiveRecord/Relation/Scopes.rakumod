
use ORM::ActiveRecord::Relation::Scope;

class Scopes is export {
  my @.scopes of Scope;
  my %by-name;      # scope name => Array of Scope
  my %registered;   # owning class name + scope name => True

  # A model's `submethod BUILD` runs on every instantiation, so `scope` is
  # re-declared for every record built. Registering by (owning class, name)
  # keeps one entry per declaration instead of one per record.
  method register(Scope:D $scope) {
    my $key = $scope.klass.^name ~ "\t" ~ $scope.name;
    return False if %registered{$key};

    %registered{$key} = True;
    @.scopes.push($scope);
    %by-name{$scope.name}.push($scope);

    True;
  }

  # Scopes are matched by name AND owning class, so two models may each define a
  # scope of the same name (e.g. Tag.ordered and Page.ordered) without colliding.
  # The name index makes the lookup a hash miss for the vast majority of
  # `FALLBACK` names, which are attributes rather than scopes.
  # The scope is named explicitly rather than through the topic: smartmatch
  # binds `$_` to its left side while evaluating its right, so a bare `.klass`
  # would resolve against the model class, not the scope.
  method !find(Str:D $name, Mu:U $klass) {
    return Nil unless %by-name{$name}:exists;
    %by-name{$name}.first(-> $scope { $klass ~~ $scope.klass });
  }

  method exec(Str:D $name, Mu:U $klass, |args) {
    with self!find($name, $klass) -> $scope {
      return $scope.block()(|args);
    }

    die qq{Scope "$name" not found for {$klass.^name}};
  }

  method exists(Str:D $name, Mu:U $klass --> Bool) {
    so self!find($name, $klass);
  }
}
