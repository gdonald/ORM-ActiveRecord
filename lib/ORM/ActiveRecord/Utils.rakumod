
class Utils is export {
  method base-name(Str $name) {
    $name.split('::').first(:end);
  }

  multi method table-name(Mu:D $obj) {
    Utils.base-name($obj.WHAT.perl.lc) ~ 's';
  }

  multi method table-name(Mu:U $type) {
    $type.^name.lc ~ 's';
  }

  method singular(Str:D $name) {
    $name.subst(/s$/, '');
  }

  method to-foreign-key(Str:D $name) {
    Utils.singular($name) ~ '_id';
  }
}
