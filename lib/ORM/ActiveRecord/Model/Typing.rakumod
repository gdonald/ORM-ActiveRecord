
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
  has %.virtual-attributes;   # declared attributes with no backing column

  method attribute(Str:D $name, $type = Nil, :$default) {
    my $resolved = do given $type {
      when AttributeType { $type }
      when Str           { Type.lookup($type) }
      default            { Nil }
    };

    %!attribute-types{$name}    = $resolved if $resolved.defined;
    %!attribute-defaults{$name} = $default  if $default.defined;

    # An attribute that maps to no column is virtual: give it a slot so it can
    # be read and written like any other, but keep it out of the persisted set.
    unless self.fields.first({ .name eq $name }) {
      %!virtual-attributes{$name} = True;
      self.attrs{$name} = Any unless self.attrs{$name}:exists;
    }

    self;
  }

  method is-virtual-attribute(Str:D $name --> Bool) {
    %!virtual-attributes{$name}:exists;
  }

  method serialize(Str:D $name, $coder) {
    %!attribute-types{$name} = SerializedType.new(:$coder);
    self;
  }

  has %.store-accessors;   # accessor key => backing column

  # Serialize a column and expose named accessors that read / write keys inside
  # the stored hash (e.g. `record.theme` <-> `prefs<theme>`).
  method store(Str:D $column, :@accessors, :$coder = JsonCoder.new) {
    self.serialize($column, $coder);
    self.attribute($column, :default(-> { %() }));
    self.store-accessor($column, |@accessors);
    self;
  }

  # Add store accessors to an already-serialized column after the fact.
  method store-accessor(Str:D $column, *@keys) {
    %!store-accessors{$_.Str} = $column for @keys;
    self;
  }

  method store-accessor-column(Str:D $key) {
    %!store-accessors{$key};
  }

  # Cast declared attributes once an instance is built. DB-loaded records use
  # `deserialize`; freshly-built records apply defaults then `cast`. A virtual
  # attribute has no column value, so it also takes its default on load.
  method apply-attribute-types {
    return self unless %!attribute-types || %!attribute-defaults;

    if self.was-found-from-db {
      for %!attribute-defaults.kv -> $name, $def {
        next unless self.is-virtual-attribute($name);
        next if self.attrs{$name}.defined;
        self.attrs{$name} = $def ~~ Callable ?? $def.() !! $def;
      }

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

  # The subset of `attrs-to-persist` an UPDATE has to write: the columns whose
  # value differs from the row this record was loaded from. Leaving an unchanged
  # column out shrinks the statement and stops two concurrent saves that touch
  # different columns from overwriting each other.
  method changed-attrs-to-persist(--> Hash) {
    my %all = self.attrs-to-persist;
    my %changed;

    for self.changed -> $name {
      %changed{$name} = %all{$name} if %all{$name}:exists;
    }

    # Dirty tracking compares an attribute against the snapshot taken when the
    # record was loaded, and a hash or array attribute is mutated in place, so
    # both sides move together and the change is invisible. A column with a
    # declared type, and any whose value is a container, is always written.
    for %all.kv -> $name, $value {
      next if %changed{$name}:exists;
      next unless %!attribute-types{$name}:exists
               || self.attrs{$name} ~~ Associative
               || self.attrs{$name} ~~ Positional;
      %changed{$name} = $value;
    }

    %changed;
  }

  # The attribute hash to persist, with declared types serialized to their DB
  # representation. Identity when no types are declared.
  method attrs-to-persist(--> Hash) {
    my %out = self.attrs;
    return %out unless %!attribute-types || %!virtual-attributes;

    for %!attribute-types.kv -> $name, $type {
      next unless %out{$name}:exists;
      %out{$name} = $type.serialize(%out{$name});
    }

    %out{$_}:delete for %!virtual-attributes.keys;

    %out;
  }
}
