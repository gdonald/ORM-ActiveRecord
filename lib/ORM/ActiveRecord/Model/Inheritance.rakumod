
use ORM::ActiveRecord::Support::Utils;

# Single-table inheritance. A base model maps to a table that carries an
# inheritance column (default `type`); subclasses share that table. Reads
# dispatch each row to the class named by its type value; writes populate the
# type column with the row's class; and a subclass scopes its finders to its
# own rows. Standalone models (no Model subclass and no Model ancestor) are
# never treated as STI, so a plain `type` column does not trigger it.
role ModelInheritance is export {
  my $MODEL-NAME = 'Model';

  my %sti-abstract;            # class name => Bool
  my %sti-inheritance-column;  # class name => column name
  my %sti-name-override;       # class name => stored type value
  my %sti-store-full;          # class name => Bool
  my %sti-registered;          # class name => class
  my %sti-by-name;             # stored type value => class

  # ---- class-level configuration (call right after the class definition) ----

  method abstract-class(*@set) {
    if @set { %sti-abstract{self.^name} = ?@set[0]; return self }
    so %sti-abstract{self.^name};
  }

  method inheritance-column(*@set) {
    if @set { %sti-inheritance-column{self.^name} = @set[0].Str; return self }
    self!sti-inherited(%sti-inheritance-column) // 'type';
  }

  method store-full-sti-class(*@set) {
    if @set { %sti-store-full{self.^name} = ?@set[0]; return self }
    self!sti-inherited(%sti-store-full) // True;
  }

  method sti-name(*@set) {
    if @set { %sti-name-override{self.^name} = @set[0].Str; return self }
    return %sti-name-override{self.^name} if %sti-name-override{self.^name}:exists;
    self.store-full-sti-class ?? self.^name !! Utils.base-name(self.^name);
  }

  # Walk the class linearization so a subclass inherits a base's setting.
  method !sti-inherited(%store) {
    for self.^mro -> $ancestor {
      return %store{$ancestor.^name} if %store{$ancestor.^name}:exists;
    }
    Nil;
  }

  # ---- hierarchy predicates ----

  # The highest non-abstract model ancestor: the class that owns the table.
  method sti-base-class {
    my $base = self;
    for self.^mro -> $ancestor {
      next if $ancestor === self;
      last if $ancestor.^name eq $MODEL-NAME;
      next unless $ancestor.^can('abstract-class');
      $base = $ancestor unless $ancestor.abstract-class;
    }
    $base;
  }

  method descends-from-active-record(--> Bool) {
    return True if self.abstract-class;
    self.sti-base-class === self;
  }

  method sti-active(--> Bool) {
    return False if self.abstract-class;
    return True unless self.descends-from-active-record;
    so self.sti-descendants.grep({ $_ !=== self });
  }

  # ---- registry ----

  method register-sti {
    return if %sti-registered{self.^name}:exists;
    %sti-registered{self.^name} = self;
    %sti-by-name{self.sti-name} = self;
  }

  method sti-descendants {
    %sti-registered.values.grep({ $_.^isa(self) });
  }

  method sti-class-for(Str() $type-value) {
    return self unless $type-value.defined && $type-value.chars;

    # A resolved class is a type object, so test it with ^can rather than
    # .defined (which is False for every type object).
    my $resolved = try self.resolve-class-name($type-value);
    if $resolved.^can('sti-active') {
      $resolved.register-sti;
      return $resolved;
    }

    if %sti-by-name{$type-value}:exists {
      my $cls = %sti-by-name{$type-value};
      $cls.register-sti;
      return $cls;
    }

    self;
  }

  # ---- read / write hooks ----

  method instantiate-record(%record, :@fields) {
    my $actual = self;

    if self.sti-active {
      my $type-value = %record{self.inheritance-column};
      $actual = self.sti-class-for($type-value) if $type-value.defined && $type-value.chars;
    }

    $actual.new(id => (%record<id> // 0), record => { attrs => %record, :@fields });
  }

  method apply-sti-type {
    return unless self.WHAT.sti-active;
    my $column = self.WHAT.inheritance-column;
    return unless self.has-attribute($column);
    self.attrs{$column} = self.WHAT.sti-name;
  }

  # The type values a subclass finder restricts to: itself and its descendants.
  method sti-scope-names {
    my @names = self.sti-descendants.map(*.sti-name).unique.List;
    @names ?? @names !! (self.sti-name,);
  }
}
