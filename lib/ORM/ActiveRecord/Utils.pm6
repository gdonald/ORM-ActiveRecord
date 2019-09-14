
class Utils is export {
  method base-name(Str $name) {
    $name.split('::').first(:end);
  }

  method table-name(Mu:D $obj) {
    Utils.base-name($obj.WHAT.perl.lc) ~ 's';
  }
}