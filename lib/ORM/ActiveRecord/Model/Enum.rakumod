
use ORM::ActiveRecord::Type;

# Rails-style enums. Declare one in the model's `submethod BUILD`, the same
# place attributes / validations / associations are declared:
#
#   self.enum: 'status', { active => 0, archived => 1 };
#
# The column stores the backing value (integer or text); the in-memory value is
# the symbolic name. Declaring an enum gives each value a predicate
# (`record.is-active`), a bang setter that assigns and saves
# (`record.active-bang`), and a class scope (`Order.active`).
role ModelEnum is export {
  my %enum-mapping;   # class name => { attr => { symbol => backing } }

  method enum(Str:D $attr, %mapping) {
    %enum-mapping{self.WHAT.^name}{$attr} = %mapping.hash;
    self.attribute($attr, EnumType.new(mapping => %mapping.hash));
    self;
  }

  # Merge enum declarations up the class hierarchy, with subclasses winning.
  method enum-definitions {
    my %merged;
    for self.^mro.reverse -> $ancestor {
      with %enum-mapping{$ancestor.^name} -> %defs {
        %merged{.key} = .value for %defs;
      }
    }
    %merged;
  }

  method enum-attr-for-value(Str:D $value) {
    for self.enum-definitions.kv -> $attr, %mapping {
      return $attr if %mapping{$value}:exists;
    }
    Nil;
  }

  method enum-backing(Str:D $attr, Str:D $symbol) {
    self.enum-definitions{$attr}{$symbol};
  }

  method enum-values(Str:D $attr) {
    (self.enum-definitions{$attr} // %()).keys.sort.list;
  }
}
