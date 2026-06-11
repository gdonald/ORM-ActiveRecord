
# Composite and custom primary keys. A model whose rows are identified by more
# than one column declares it with `primary-key`; a model that keeps `id` as its
# key but locates rows for writes by extra columns declares `query-constraints`.
# Both default to the single `id` column, so an ordinary model is unaffected.
role ModelPrimaryKey is export {
  my %primary-key-of;        # class name => list of column names
  my %query-constraints-of;  # class name => list of column names

  # ---- class-level configuration (call right after the class definition) ----

  method primary-key(*@set) {
    if @set {
      %primary-key-of{self.^name} = self!normalize-columns(@set);
      return self;
    }
    my @cols = self.primary-keys;
    @cols.elems == 1 ?? @cols[0] !! @cols.List;
  }

  method query-constraints(*@set) {
    if @set {
      %query-constraints-of{self.^name} = self!normalize-columns(@set);
      return self;
    }
    (self!pk-inherited(%query-constraints-of) // ()).List;
  }

  # ---- resolved views used by finders and persistence ----

  method primary-keys(--> List) {
    (self!pk-inherited(%primary-key-of) // ('id',)).List;
  }

  method has-composite-primary-key(--> Bool) {
    self.primary-keys.elems > 1;
  }

  # The columns that locate one row for update / delete / reload. Query
  # constraints win when set, otherwise the primary key columns.
  method locating-columns(--> List) {
    my @qc = self.query-constraints;
    @qc.elems ?? @qc.List !! self.primary-keys;
  }

  method default-id-locating(--> Bool) {
    my @cols = self.locating-columns;
    @cols.elems == 1 && @cols[0] eq 'id';
  }

  method !normalize-columns(@set --> List) {
    my @cols = @set.elems == 1 && @set[0] ~~ Positional ?? @set[0].list !! @set.list;
    @cols.map(*.Str).list;
  }

  # Walk the class linearization so a subclass inherits a base's setting.
  method !pk-inherited(%store) {
    for self.^mro -> $ancestor {
      return %store{$ancestor.^name} if %store{$ancestor.^name}:exists;
    }
    Nil;
  }
}
