
use ORM::ActiveRecord::Schema::Field;

class Error is export {
  has Field $.field;
  has Str   $.message;
  has Str   $.type    = 'invalid';
  has       %.options;

  method attribute( --> Str ) {
    $!field.defined ?? $!field.name !! 'base';
  }

  method full-message( --> Str ) {
    my $attr = self.attribute;

    return $!message if $attr eq 'base';

    "$attr $!message";
  }

  method match(Str :$attribute, :$type, *%opts --> Bool) {
    return False if $attribute.defined && $attribute ne self.attribute;

    if $type.defined {
      my $t = $type ~~ Pair ?? $type.key !! ~$type;
      return False if $t ne $!type;
    }

    for %opts.kv -> $k, $v {
      return False unless %!options{$k}:exists && %!options{$k} eqv $v;
    }

    True;
  }

  method detail( --> Hash ) {
    my %d = error => $!type;

    for %!options.kv -> $k, $v { %d{$k} = $v }

    %d;
  }
}
