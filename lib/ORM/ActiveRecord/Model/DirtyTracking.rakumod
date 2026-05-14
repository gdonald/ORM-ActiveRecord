
use ORM::ActiveRecord::Errors::X;

role ModelDirtyTracking is export {
  method is-dirty(--> Bool) {
    for self.attrs.keys -> $key { return True if self.attrs«$key» !eqv self.attrs-db«$key» }
    False;
  }

  method is-changed(--> Bool) {
    return True if self.will-change.elems;
    for self.attrs.keys -> $key { return True if self.attrs«$key» !eqv self.attrs-db«$key» }
    False;
  }

  method changed() {
    my @names;
    for self.attrs.keys.sort -> $key {
      @names.push($key) if self.will-change{$key} || self.attrs«$key» !eqv self.attrs-db«$key»;
    }
    @names.list;
  }

  method changes(--> Hash) {
    my %h;
    for self.changed -> $name {
      %h{$name} = [self.attrs-db{$name}, self.attrs{$name}];
    }
    %h;
  }

  method changed-attributes(--> Hash) {
    my %h;
    for self.changed -> $name {
      %h{$name} = self.attrs-db{$name};
    }
    %h;
  }

  method is-attribute-changed(Str:D $name --> Bool) {
    so self.will-change{$name} || (self.attrs«$name» !eqv self.attrs-db«$name»);
  }

  method attribute-was(Str:D $name) {
    self.is-attribute-changed($name) ?? self.attrs-db{$name} !! self.attrs{$name};
  }

  method attribute-change(Str:D $name) {
    return Nil unless self.is-attribute-changed($name);
    [self.attrs-db{$name}, self.attrs{$name}];
  }

  method attribute-will-change(Str:D $name) {
    self.will-change{$name} = True;
    self;
  }

  method is-saved-change-to(Str:D $name --> Bool) {
    self.previous-changes{$name}:exists;
  }

  method saved-change-to(Str:D $name) {
    self.previous-changes{$name} // Nil;
  }

  method attribute-before-last-save(Str:D $name) {
    self.previous-changes{$name}:exists
      ?? self.previous-changes{$name}[0]
      !! self.attrs{$name};
  }

  method restore-attributes {
    die X::FrozenRecord.new(model => self.WHAT.^name) if self.is-destroyed;
    for self.attrs.keys -> $key {
      self.attrs{$key} = self.attrs-db{$key} if self.attrs-db{$key}:exists;
    }
    self.will-change = ();
    self;
  }

  method restore-attribute(Str:D $name) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if self.is-destroyed;
    self.attrs{$name} = self.attrs-db{$name} if self.attrs-db{$name}:exists;
    self.will-change{$name}:delete;
    self;
  }

  method reset-attribute(Str:D $name) {
    self.restore-attribute($name);
  }

  method reload {
    die X::FrozenRecord.new(model => self.WHAT.^name) if self.is-destroyed;
    return self if self.id == 0;
    self.get-attrs(:id(self.id));
    self.will-change = ();
    self;
  }
}
