
use ORM::ActiveRecord::Type;

# Per-attribute type declarations on a model. Declare these in the model's
# `submethod BUILD` (the same place associations / scopes are declared):
#
#   self.attribute('tags', CsvType.new);            # custom type
#   self.attribute('level', :default(5));            # block / value default
#   self.attribute('rank', 'integer');               # a registered type by name
#   self.serialize('prefs', JsonCoder.new);          # serialized column
#
# Type casting is applied after construction (`apply-attribute-types`, called
# from `Model.new`) and on write (`attrs-to-persist`, used by the adapters),
# so it does not depend on BUILD ordering.
role ModelTyping is export {
  has %.attribute-types;
  has %.attribute-defaults;

  method attribute(Str:D $name, $type = Nil, :$default) {
    my $resolved = do given $type {
      when AttributeType { $type }
      when Str           { Type.lookup($type) }
      default            { Nil }
    };

    %!attribute-types{$name}    = $resolved if $resolved.defined;
    %!attribute-defaults{$name} = $default  if $default.defined;

    self;
  }

  method serialize(Str:D $name, $coder) {
    %!attribute-types{$name} = SerializedType.new(:$coder);
    self;
  }

  # Cast declared attributes once an instance is built. DB-loaded records use
  # `deserialize`; freshly-built records apply defaults then `cast`.
  method apply-attribute-types {
    return self unless %!attribute-types || %!attribute-defaults;

    if self.was-found-from-db {
      for %!attribute-types.kv -> $name, $type {
        next unless self.attrs{$name}:exists;
        self.attrs{$name} = $type.deserialize(self.attrs{$name});
      }
    }
    else {
      my %given = (self.record<attrs> // %()).hash;

      for %!attribute-defaults.kv -> $name, $def {
        next if %given{$name}:exists;
        self.attrs{$name} = $def ~~ Callable ?? $def.() !! $def;
      }

      for %!attribute-types.kv -> $name, $type {
        next unless self.attrs{$name}:exists;
        self.attrs{$name} = $type.cast(self.attrs{$name});
      }
    }

    self;
  }

  # The attribute hash to persist, with declared types serialized to their DB
  # representation. Identity when no types are declared.
  method attrs-to-persist(--> Hash) {
    my %out = self.attrs;
    return %out unless %!attribute-types;

    for %!attribute-types.kv -> $name, $type {
      next unless %out{$name}:exists;
      %out{$name} = $type.serialize(%out{$name});
    }

    %out;
  }
}
