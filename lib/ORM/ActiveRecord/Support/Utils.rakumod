
class Utils is export {
  method base-name(Str $name) {
    $name.split('::').first(:end);
  }

  method lookup-class(Str:D $name) {
    return Nil unless $name;
    my @parts = $name.split('::').grep(*.chars);
    return Nil unless @parts.elems;

    my $current := GLOBAL;
    for @parts -> $part {
      my %stash := $current.WHO;
      return Nil unless %stash{$part}:exists;
      my $next := %stash{$part};
      return Nil if $next === Any;
      return Nil if $next ~~ Failure;
      $current := $next;
    }
    $current;
  }

  multi method table-name(Mu:D $obj) {
    return $obj.table-name if $obj.^can('table-name');
    Utils.base-name($obj.WHAT.raku.lc) ~ 's';
  }

  multi method table-name(Mu:U $type) {
    return $type.table-name if $type.^can('table-name');
    Utils.base-name($type.^name).lc ~ 's';
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
