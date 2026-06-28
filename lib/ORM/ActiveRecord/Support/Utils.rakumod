
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

  # Convert a (possibly namespaced) CamelCase class name to snake_case:
  # 'PageTag' -> 'page_tag', 'Foo::HotItem' -> 'hot_item'.
  method underscore(Str:D $name) {
    Utils.base-name($name).subst(/(<[a..z0..9]>)(<[A..Z]>)/, { "$0_$1" }, :g).lc;
  }

  # Rails-style table name: snake_case the class name, then pluralize.
  method tableize(Str:D $name) {
    Utils.underscore($name) ~ 's';
  }

  multi method table-name(Mu:D $obj) {
    return $obj.table-name if $obj.^can('table-name');
    Utils.tableize($obj.WHAT.^name);
  }

  multi method table-name(Mu:U $type) {
    return $type.table-name if $type.^can('table-name');
    Utils.tableize($type.^name);
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
