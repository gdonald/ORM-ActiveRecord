
use ORM::ActiveRecord::Support::Utils;

# A description of one declared association, returned by reflection. `macro` is
# the kind ('belongs-to', 'has-many', 'has-one', 'has-and-belongs-to-many');
# `klass` is the resolved target class (Mu for an unresolved or polymorphic
# belongs-to).
class AssociationReflection is export {
  has Str  $.name;
  has Str  $.macro;
  has      $.klass;
  has Str  $.class-name;
  has Str  $.foreign-key;
  has Str  $.primary-key;
  has Bool $.polymorphic = False;
  has Str  $.through;
  has Str  $.source;

  method is-collection(--> Bool) {
    so $!macro eq 'has-many' | 'has-and-belongs-to-many';
  }

  method is-singular(--> Bool) {
    !self.is-collection;
  }
}

# Public class-level reflection so tools can build, stub, and validate records
# without reaching into model internals. Every method works on the class or on
# an instance; class calls construct a throwaway probe to read the per-instance
# association and field declarations.
role ModelReflection is export {
  my Int $stub-counter = 1_000_000;

  method !reflect-probe {
    self.defined ?? self !! self.new(:id(0));
  }

  # ---- associations ----

  method association-names {
    my $probe = self!reflect-probe;
    (
      |$probe.belongs-tos.keys,
      |$probe.has-manys.keys,
      |$probe.has-ones.keys,
      |$probe.habtms.keys,
    ).sort.list;
  }

  method associations {
    self.association-names.map({ self.reflect-on-association($_) }).list;
  }

  method reflect-on-association(Str:D $name) {
    my $probe = self!reflect-probe;

    return self!build-reflection($probe, 'belongs-to', $name, $probe.belongs-tos{$name})
      if $probe.belongs-tos{$name}:exists;
    return self!build-reflection($probe, 'has-many', $name, $probe.has-manys{$name})
      if $probe.has-manys{$name}:exists;
    return self!build-reflection($probe, 'has-one', $name, $probe.has-ones{$name})
      if $probe.has-ones{$name}:exists;
    return self!build-reflection($probe, 'has-and-belongs-to-many', $name, $probe.habtms{$name})
      if $probe.habtms{$name}:exists;

    Nil;
  }

  method !build-reflection($probe, Str:D $macro, Str:D $name, $spec) {
    my $polymorphic = $macro eq 'belongs-to' && $probe.is-polymorphic-assoc($name);

    my $fk-default = $macro eq 'belongs-to'
      ?? $name ~ '_id'
      !! Utils.base-name($probe.fkey-name);

    my $klass = $polymorphic ?? Mu !! $probe.assoc-class-from-spec($spec);

    my $through = $probe.assoc-spec-has($spec, 'through')
      ?? ~$probe.assoc-spec-value($spec, 'through')
      !! Str;

    my $source = $through.defined
      ?? $probe.assoc-source-name($spec, Utils.singular($name))
      !! Str;

    my $class-name = $probe.assoc-spec-has($spec, 'class-name')
      ?? ~$probe.assoc-spec-value($spec, 'class-name')
      !! ($klass.defined ?? Utils.base-name($klass.^name) !! Str);

    AssociationReflection.new(
      :$name, :$macro, :$klass, :$class-name,
      foreign-key => $probe.assoc-fkey-from-spec($spec, $fk-default),
      primary-key => $probe.assoc-pkey-from-spec($spec, 'id'),
      :$polymorphic, :$through, :$source,
    );
  }

  # ---- columns / attributes ----

  method column-names {
    self!reflect-probe.fields.map(*.name).list;
  }

  method columns {
    my $probe = self!reflect-probe;
    $probe.db.column-details(table => $probe.table-name).list;
  }

  method column(Str:D $name) {
    self.columns.first({ .<name> eq $name });
  }

  method column-type(Str:D $name) {
    my $col = self.column($name);
    $col ?? $col<type> !! Str;
  }

  # ---- primary key ----

  method primary-key-type {
    self.column-type(self.primary-keys[0]);
  }

  # ---- enums ----

  method enums {
    self!reflect-probe;          # ensure BUILD has registered the enum declarations
    self.enum-definitions;
  }

  # ---- stubs ----

  method build-stubbed(%attrs = {}) {
    my $obj = self.build(%attrs);

    $obj.id = ++$stub-counter;

    my $now = DateTime.now;
    for $obj.fields -> $field {
      $obj.attrs<created_at> //= $now if $field.name eq 'created_at';
      $obj.attrs<updated_at> //= $now if $field.name eq 'updated_at';
    }

    $obj.was-persisted    = True;
    $obj.was-found-from-db = True;
    $obj.make-readonly;
    $obj.is-stubbed = True;

    $obj;
  }
}
