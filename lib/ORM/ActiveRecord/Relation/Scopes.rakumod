
use ORM::ActiveRecord::Relation::Scope;

class Scopes is export {
  my @.scopes of Scope;

  # Scopes are matched by name AND owning class, so two models may each define a
  # scope of the same name (e.g. Tag.ordered and Page.ordered) without colliding.
  method exec(Str:D $name, Mu:U $klass, |args) {
    for Scopes.scopes -> $scope {
      next unless $scope.name eq $name;
      next unless $klass ~~ $scope.klass;
      return $scope.block()(|args);
    }

    die qq{Scope "$name" not found for {$klass.^name}};
  }

  method exists(Str:D $name, Mu:U $klass --> Bool) {
    for Scopes.scopes -> $scope {
      return True if $scope.name eq $name && $klass ~~ $scope.klass;
    }

    False;
  }
}
