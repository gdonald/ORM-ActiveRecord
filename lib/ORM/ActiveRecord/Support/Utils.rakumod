
class Utils is export {
  method base-name(Str $name) {
    $name.split('::').first(:end);
  }

  multi method table-name(Mu:D $obj) {
    Utils.base-name($obj.WHAT.raku.lc) ~ 's';
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

  method fnv1a-hex(Str:D $s --> Str) {
    my Int $h = 0xcbf29ce484222325;
    my Int $mask = 0xFFFFFFFFFFFFFFFF;
    for $s.encode('utf8').list -> $b {
      $h = ($h +^ $b) +& $mask;
      $h = ($h * 0x100000001b3) +& $mask;
    }
    $h.fmt('%016x');
  }
}
