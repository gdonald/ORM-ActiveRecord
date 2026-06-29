
use ORM::ActiveRecord::Schema::Field;

class Scope is export {
  has $.klass;
  has Str $.name;
  has Block $.block;
}

# Marker mixed into a method by the `is scope` trait. It travels with the method
# into the precompiled class, so a relation's FALLBACK can recognise a scope by
# introspecting the model's methods (the global Scope registry built at compile
# time does not survive precompilation across separate modules).
role IsScope is export { }

