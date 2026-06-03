
use JSON::Tiny;

# The attribute type-system: a small casting layer that sits at the model
# boundary, on top of the adapter's column-type coercion.
#
#   cast        — user input → Raku value (build / assign)
#   deserialize — DB value   → Raku value (read), defaults to cast
#   serialize   — Raku value  → DB value  (write)
role AttributeType is export {
  method cast($value)        { $value }
  method deserialize($value) { self.cast($value) }
  method serialize($value)   { $value }
}

class IntegerType does AttributeType is export {
  method cast($v)      { $v.defined ?? $v.Int !! $v }
  method serialize($v) { $v.defined ?? $v.Int !! $v }
}

class StringType does AttributeType is export {
  method cast($v)      { $v.defined ?? $v.Str !! $v }
  method serialize($v) { $v.defined ?? $v.Str !! $v }
}

class BooleanType does AttributeType is export {
  method cast($v) {
    return $v if $v ~~ Bool;
    return $v unless $v.defined;
    my $s = $v.Str.lc;
    so $s eq 'true' | 't' | '1' | 'y' | 'yes';
  }
  method serialize($v) { self.cast($v) }
}

class FloatType does AttributeType is export {
  method cast($v)      { $v.defined ?? $v.Num !! $v }
  method serialize($v) { $v.defined ?? $v.Num !! $v }
}

class DecimalType does AttributeType is export {
  method cast($v)      { $v.defined ?? $v.Numeric !! $v }
  method serialize($v) { $v.defined ?? $v.Str !! $v }
}

class DateTimeType does AttributeType is export {
  method cast($v) {
    return $v if $v ~~ DateTime | Date;
    return $v unless $v.defined && $v.Str.chars;
    my $iso = $v.Str.subst(' ', 'T');
    $iso ~~ /^ \d ** 4 '-' \d\d '-' \d\d 'T' \d\d ':' \d\d ':' \d\d / ?? DateTime.new($iso) !! $v;
  }
  method serialize($v) { $v }
}

# Coder for serialized columns. Any object responding to `.dump` / `.load`
# works as a custom coder (YAML / MessagePack / app-specific); JsonCoder is
# built in.
class JsonCoder is export {
  method dump($v)  { to-json($v) }
  method load($s)  {
    return $s unless $s.defined && $s.Str.chars;
    from-json($s.Str);
  }
}

class SerializedType does AttributeType is export {
  has $.coder is required;
  method cast($v)        { $v }                 # user supplies a Raku value
  method deserialize($v) { $!coder.load($v) }
  method serialize($v)   { $!coder.dump($v) }
}

# The type registry: name → AttributeType. Pre-seeded with the built-ins.
class Type is export {
  my %registry;

  method register(Str:D $name, AttributeType:D $type) {
    %registry{$name} = $type;
  }

  method lookup(Str:D $name) {
    %registry{$name};
  }

  method is-registered(Str:D $name --> Bool) {
    %registry{$name}:exists;
  }

  method names {
    %registry.keys.sort.list;
  }
}

Type.register('integer',  IntegerType.new);
Type.register('string',   StringType.new);
Type.register('boolean',  BooleanType.new);
Type.register('float',    FloatType.new);
Type.register('decimal',  DecimalType.new);
Type.register('datetime', DateTimeType.new);
