
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::Utils;

role CollectionProxy is export {
  has Mu $.owner       is rw;
  has $.spec           is rw;
  has Mu $.target-class is rw;
  has Str $.assoc-name is rw;
  has @.args           is rw;

  method records { self.list }

  method is-empty(--> Bool) { self.elems == 0 }
  method is-any(--> Bool)   { self.elems > 0  }
  method size(--> Int)      { self.elems }
  method length(--> Int)    { self.elems }

  multi method count(--> Int)            { self.elems }
  multi method count(Str:D $col --> Int) {
    self.grep({ .attrs{$col}.defined }).elems;
  }

  multi method exists(--> Bool)           { self.elems > 0 }
  multi method exists(Int:D $id --> Bool) {
    self.first(*.id == $id).defined;
  }
  multi method exists(Hash:D $conds --> Bool) {
    self.first(-> $r {
      [&&] $conds.kv.map(-> $k, $v { ($r.attrs{$k} // Any) eqv $v })
    }).defined;
  }

  method find(Int:D $id) {
    my $r = self.first(*.id == $id);
    die X::RecordNotFound.new(:model($!target-class.^name), :$id) unless $r.defined;
    $r;
  }

  method build(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    $!target-class.build(%a);
  }

  method create(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    my $r = $!target-class.create(%a);
    self.Array::push($r) if $r.id;
    $r;
  }

  method create-or-die(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    my $r = $!target-class.create-or-die(%a);
    self.Array::push($r);
    $r;
  }

  method push(Mu:D $record) {
    self!link($record);
    self.Array::push($record) unless self.first(*.id == $record.id).defined;
    self;
  }

  method append(Mu:D $record) { self.push($record) }

  method clear {
    my $strategy = self!dependent-strategy;
    for self.list -> $r { self!unlink-one($r, $strategy) }
    self.splice(0, self.elems);
    self;
  }

  method delete(*@to-remove) {
    my $strategy = self!dependent-strategy || 'nullify';
    for @to-remove -> $r { self!unlink-one($r, $strategy) }
    my %ids = @to-remove.map({ .id => True }).Hash;
    my @keep = self.grep({ not %ids{.id} });
    self.splice(0, self.elems, @keep);
    self;
  }

  method destroy(*@to-remove) {
    for @to-remove -> $r {
      self!unlink-through-join($r);
      $r.destroy;
    }
    my %ids = @to-remove.map({ .id => True }).Hash;
    my @keep = self.grep({ not %ids{.id} });
    self.splice(0, self.elems, @keep);
    self;
  }

  method replace(@new) {
    my %new-ids = @new.map({ .id => True }).Hash;
    my $strategy = self!dependent-strategy || 'nullify';
    for self.list -> $r {
      next if %new-ids{$r.id};
      self!unlink-one($r, $strategy);
    }
    self.splice(0, self.elems);
    for @new -> $r { self.push($r) }
    self;
  }

  method !apply-fkey(%attrs) {
    my %a = %attrs;
    if self!is-polymorphic-as {
      my $as = self!as-name;
      %a{$as ~ '_id'}   = self!owner-pkey-val;
      %a{$as ~ '_type'} = Utils.base-name($!owner.WHAT.^name);
    } else {
      %a{self!fkey-col} = self!owner-pkey-val;
    }
    %a;
  }

  method !link(Mu:D $record) {
    if self!is-through {
      self!link-through($record);
      return;
    }
    if self!is-polymorphic-as {
      my $as = self!as-name;
      $record.attrs{$as ~ '_id'}   = self!owner-pkey-val;
      $record.attrs{$as ~ '_type'} = Utils.base-name($!owner.WHAT.^name);
    } else {
      $record.attrs{self!fkey-col} = self!owner-pkey-val;
    }
    $record.save;
  }

  method !unlink-one(Mu:D $record, Str:D $strategy) {
    if self!is-through {
      self!unlink-through($record);
      return;
    }
    given $strategy {
      when 'destroy'    { $record.destroy }
      when 'delete-all' { $record.delete }
      default           { self!nullify-fkey($record) }
    }
  }

  method !nullify-fkey(Mu:D $record) {
    my $table = Utils.table-name($record);
    if self!is-polymorphic-as {
      my $as = self!as-name;
      my $id-col   = $as ~ '_id';
      my $type-col = $as ~ '_type';
      my $stmt = DB.shared.sanitize-sql-array([
        "UPDATE $table SET $id-col = NULL, $type-col = NULL WHERE id = ?",
        $record.id,
      ]);
      DB.shared.exec-stmt($stmt);
      $record.attrs{$id-col}   = 0;
      $record.attrs{$type-col} = '';
    } else {
      my $col = self!fkey-col;
      my $stmt = DB.shared.sanitize-sql-array([
        "UPDATE $table SET $col = NULL WHERE id = ?",
        $record.id,
      ]);
      DB.shared.exec-stmt($stmt);
      $record.attrs{$col} = 0;
    }
  }

  method !unlink-through(Mu:D $record) {
    my $join-table = self!through-join-table;
    return unless $join-table;
    my $owner-key  = self!through-owner-key;
    my $target-key = Utils.to-foreign-key($!assoc-name);
    DB.shared.delete-records(
      :table($join-table),
      :where(%($owner-key => self!owner-pkey-val, $target-key => $record.id)),
    );
  }

  method !unlink-through-join(Mu:D $record) {
    self!unlink-through($record) if self!is-through;
  }

  method !link-through(Mu:D $record) {
    $record.save if $record.id == 0;
    my $join-table = self!through-join-table;
    my $owner-key  = self!through-owner-key;
    my $target-key = Utils.to-foreign-key($!assoc-name);
    my $stmt = DB.shared.sanitize-sql-array([
      "INSERT INTO $join-table ($owner-key, $target-key) VALUES (?, ?)",
      self!owner-pkey-val, $record.id,
    ]);
    DB.shared.exec-stmt($stmt);
  }

  method !is-through(--> Bool) {
    $!owner.assoc-spec-has($!spec, 'through');
  }

  method !through-join-table(--> Str) {
    return '' unless self!is-through;
    my $v = $!owner.assoc-spec-value($!spec, 'through');
    given $v {
      when Pair { return ~$v.key }
      default   { return ~$v }
    }
  }

  method !through-owner-key(--> Str) {
    Utils.base-name($!owner.fkey-name);
  }

  method !is-polymorphic-as(--> Bool) {
    $!owner.assoc-spec-has($!spec, 'as');
  }

  method !as-name(--> Str) {
    ~$!owner.assoc-spec-value($!spec, 'as');
  }

  method !fkey-col(--> Str) {
    my $override = $!owner.assoc-spec-has($!spec, 'foreign-key')
      ?? ~$!owner.assoc-spec-value($!spec, 'foreign-key')
      !! '';
    return $override if $override;
    Utils.base-name($!owner.fkey-name);
  }

  method !pkey-col(--> Str) {
    $!owner.assoc-spec-has($!spec, 'primary-key')
      ?? ~$!owner.assoc-spec-value($!spec, 'primary-key')
      !! 'id';
  }

  method !owner-pkey-val {
    my $pkey = self!pkey-col;
    $pkey eq 'id' ?? $!owner.id !! $!owner.attrs{$pkey};
  }

  method !dependent-strategy(--> Str) {
    $!owner.assoc-dependent($!spec);
  }
}
