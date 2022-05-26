
use ORM::ActiveRecord::Scope;

class Scopes is export {
  my @.scopes of Scope;

  method exec(Str:D $name) {
    for Scopes.scopes -> $scope {
      return $scope.block()() if $scope.name eq $name;
    }

    say 'Scope "' ~ $name ~ '" not found'; die;
  }

  method exists(Str:D $name) {
    for Scopes.scopes -> $scope {
      return True if $scope.name eq $name;
    }

    False;
  }
}
