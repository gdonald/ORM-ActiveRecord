
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::Environment;
use ORM::ActiveRecord::Support::Utils;

role CollectionProxy is export {
  has Mu $.owner       is rw;
  has $.spec           is rw;
  has Mu $.target-class is rw;
  has Str $.assoc-name is rw;
  has @.args           is rw;
  has &.relate         is rw;
  has &.load           is rw;
  has %.load-state     is rw;
  has %!member-ids;
  has Bool $!member-ids-stale = True;

  method db(--> DB) {
    # Route through DB.current so an association query uses the request's pooled
    # connection, not the process-wide shared one that many request threads
    # would otherwise drive concurrently.
    my $name = $!target-class.^can('connection-name') ?? $!target-class.connection-name !! default-connection();
    DB.current(name => $name);
  }

  method records { self.list }

  # The proxy starts as an empty Array and fetches its rows the first time
  # something reads them. Every Array operation funnels through one of the
  # overrides below, so a caller sees no difference; a caller that only counts
  # or searches never fetches the rows at all.
  method is-loaded(--> Bool) { %!load-state<loaded> // False }

  method !reify {
    return self if self.is-loaded;
    %!load-state<loaded> = True;

    my @records = &!load();
    self.Array::append(@records);

    # A collection that came back empty is not kept on the owner, so a record
    # created before the next read is still found.
    $!owner.assoc-cache-clear($!assoc-name) if %!load-state<keep> && !@records.elems;

    self;
  }

  # Membership by id, so pushing into a collection is constant time rather than
  # a scan of everything already in it. Rebuilt after any operation that
  # removes rows, each of which walks the collection anyway.
  method !member-ids(--> Hash) {
    self!reify;
    return %!member-ids unless $!member-ids-stale;

    %!member-ids = ();
    %!member-ids{.id} = True for self!rows;
    $!member-ids-stale = False;

    %!member-ids;
  }

  method !remember(Mu:D $record) { %!member-ids{$record.id} = True }

  method !forget-members { $!member-ids-stale = True }

  method iterator       { self!reify; self.Array::iterator }
  method elems          { self!reify; self.Array::elems }
  method end            { self!reify; self.Array::end }
  method AT-POS(|c)     { self!reify; self.Array::AT-POS(|c) }
  method EXISTS-POS(|c) { self!reify; self.Array::EXISTS-POS(|c) }
  method ASSIGN-POS(|c) { self!reify; self!forget-members; self.Array::ASSIGN-POS(|c) }
  method DELETE-POS(|c) { self!reify; self!forget-members; self.Array::DELETE-POS(|c) }
  method splice(|c)     { self!reify; self!forget-members; self.Array::splice(|c) }
  method Bool           { self!reify; self.Array::Bool }
  method list           { self!reify; self.Array::list }

  # A plain List over the fetched rows. Built straight off the Array iterator,
  # since `list` on an Array hands back the Array itself and delegating to it
  # would come straight back here.
  method !rows { self!reify; List.from-iterator(self.Array::iterator) }

  # These reach into the reified buffer rather than going through `iterator`,
  # so they are answered from the fetched rows instead.
  method List           { self!rows }
  method Slip           { self!rows.Slip }
  method Seq            { self!rows.Seq }
  method first(|c)      { self!rows.first(|c) }
  method head(|c)       { self!rows.head(|c) }
  method tail(|c)       { self!rows.tail(|c) }
  method sort(|c)       { self!rows.sort(|c) }
  method reverse        { self!rows.reverse }
  method join(|c)       { self!rows.join(|c) }
  method keys           { self!rows.keys }
  method values         { self!rows.values }
  method pairs          { self!rows.pairs }
  method sum            { self!rows.sum }
  method gist           { self!rows.gist }
  method Str            { self!rows.Str }

  # While the rows have not been fetched and the association is one a single
  # relation expresses, these ask the database rather than fetching every row
  # to answer from memory. Once the rows are here, memory is the cheaper answer.
  method !unloaded(--> Bool) { &!relate.defined && !self.is-loaded }

  method !related { &!relate.() }

  method is-empty(--> Bool) {
    self!unloaded ?? !self!related.limit(1).first.defined !! self.elems == 0;
  }

  method is-any(--> Bool)   { !self.is-empty }
  method size(--> Int)      { self.count }
  method length(--> Int)    { self.count }

  multi method count(--> Int) {
    self!unloaded ?? self!related.count !! self.elems;
  }

  # `COUNT(col)` counts the rows where the column is not null, which is the
  # same question, so the rows stay unfetched.
  multi method count(Str:D $col --> Int) {
    return self.grep({ .attrs{$col}.defined }).elems unless self!unloaded;
    self!related.count($col);
  }

  multi method exists(--> Bool)           { self.is-any }
  multi method exists(Int:D $id --> Bool) {
    return so self!member-ids{$id} unless self!unloaded;
    self!related.where({ id => $id }).limit(1).first.defined;
  }
  # This one is not pushed down. It compares with `eqv`, so a Str '2200' does
  # not match an Int column, where SQL equality would. Answering it in the
  # database would quietly change which records match.
  multi method exists(Hash:D $conds --> Bool) {
    self.first(-> $r {
      [&&] $conds.kv.map(-> $k, $v { ($r.attrs{$k} // Any) eqv $v })
    }).defined;
  }

  method find(Int:D $id) {
    my $r = self!unloaded
      ?? self!related.where({ id => $id }).limit(1).first
      !! self.first(*.id == $id);
    die X::RecordNotFound.new(:model($!target-class.^name), :$id) unless $r.defined;
    $r;
  }

  method build(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    $!target-class.build(%a);
  }

  method create(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    self!reify;
    my $r = $!target-class.create(%a);

    if $r.id {
      self.Array::push($r);
      self!remember($r);
    }

    $r;
  }

  method create-bang(%attrs = {}) {
    my %a = self!apply-fkey(%attrs);
    self!reify;
    my $r = $!target-class.create-bang(%a);

    self.Array::push($r);
    self!remember($r);

    $r;
  }

  method push(Mu:D $record) {
    self!reify;
    self!link($record);

    unless self!member-ids{$record.id} {
      self.Array::push($record);
      self!remember($record);
    }

    self;
  }

  method append(Mu:D $record) { self.push($record) }

  method clear {
    my $strategy = self!dependent-strategy;

    # Unlinking every member does not need to know which members there are: one
    # statement keyed on the owner's foreign key does it. So an unfetched
    # collection is cleared without fetching it at all.
    if !self.is-loaded && self!clear-by-owner($strategy) {
      %!load-state<loaded> = True;
      self!forget-members;
      return self;
    }

    self!unlink-many(self.list, $strategy);
    self.splice(0, self.elems);
    self;
  }

  # False when the association cannot be expressed as one owner-keyed
  # statement: a through association writes a join table, and `destroy` has to
  # load each record to run its callbacks.
  method !clear-by-owner(Str $strategy --> Bool) {
    return False if self!is-through;
    return False if $strategy && $strategy eq 'destroy';
    return False if $!target-class === Mu;

    my $table = Utils.table-name($!target-class);
    my $owner = self!owner-pkey-val;
    return False unless $owner.defined;

    if $strategy && $strategy eq 'delete-all' {
      self.db.delete-records(:$table, :where(self!owner-where));
      return True;
    }

    if self!is-polymorphic-as {
      my $as = self!as-name;
      self.db.exec-stmt(self.db.sanitize-sql-array([
        "UPDATE $table SET {$as}_id = NULL, {$as}_type = NULL WHERE {$as}_id = ? AND {$as}_type = ?",
        $owner, $!owner.polymorphic-name,
      ]));
    } else {
      my $col = self!fkey-col;
      self.db.exec-stmt(self.db.sanitize-sql-array([
        "UPDATE $table SET $col = NULL WHERE $col = ?",
        $owner,
      ]));
    }

    True;
  }

  method !owner-where(--> Hash) {
    if self!is-polymorphic-as {
      my $as = self!as-name;
      return %( ($as ~ '_id') => self!owner-pkey-val, ($as ~ '_type') => $!owner.polymorphic-name );
    }
    %( self!fkey-col => self!owner-pkey-val );
  }

  method delete(*@to-remove) {
    my $strategy = self!dependent-strategy || 'nullify';
    self!unlink-many(@to-remove, $strategy);
    my %ids = @to-remove.map({ .id => True }).Hash;
    my @keep = self.grep({ not %ids{.id} });
    self.splice(0, self.elems, @keep);
    self;
  }

  method destroy(*@to-remove) {
    self!unlink-through-many(@to-remove) if self!is-through;
    for @to-remove -> $r {
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
    self!unlink-many(self.list.grep({ !%new-ids{.id} }).list, $strategy);
    self.splice(0, self.elems);
    for @new -> $r { self.push($r) }
    self;
  }

  method !apply-fkey(%attrs) {
    my %a = %attrs;
    if self!is-polymorphic-as {
      my $as = self!as-name;
      %a{$as ~ '_id'}   = self!owner-pkey-val;
      %a{$as ~ '_type'} = $!owner.polymorphic-name;
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
      $record.attrs{$as ~ '_type'} = $!owner.polymorphic-name;
    } else {
      $record.attrs{self!fkey-col} = self!owner-pkey-val;
    }
    $record.save;
  }

  method !unlink-one(Mu:D $record, Str:D $strategy) {
    self!unlink-many(($record,), $strategy);
  }

  # `destroy` runs per record, since each fires its own callbacks and its own
  # dependent cascade. Nullifying a foreign key, deleting outright, and dropping
  # a join row do none of that, so each is one statement over the whole set
  # rather than one per record.
  method !unlink-many(@records, Str:D $strategy) {
    return unless @records.elems;

    if self!is-through {
      self!unlink-through-many(@records);
      return;
    }

    given $strategy {
      when 'destroy'    { .destroy for @records }
      when 'delete-all' { self!delete-many(@records) }
      default           { self!nullify-many(@records) }
    }
  }

  method !linkable-ids(@records) {
    @records.map(*.id).grep(*.defined).grep(* != 0).unique.list;
  }

  method !nullify-many(@records) {
    my @ids = self!linkable-ids(@records);
    return unless @ids.elems;

    my $table = Utils.table-name(@records[0]);
    my $slots = @ids.map({ '?' }).join(', ');

    if self!is-polymorphic-as {
      my $as       = self!as-name;
      my $id-col   = $as ~ '_id';
      my $type-col = $as ~ '_type';

      self.db.exec-stmt(self.db.sanitize-sql-array([
        "UPDATE $table SET $id-col = NULL, $type-col = NULL WHERE id IN ($slots)",
        |@ids,
      ]));

      for @records { .attrs{$id-col} = 0; .attrs{$type-col} = '' }
    } else {
      my $col = self!fkey-col;

      self.db.exec-stmt(self.db.sanitize-sql-array([
        "UPDATE $table SET $col = NULL WHERE id IN ($slots)",
        |@ids,
      ]));

      .attrs{$col} = 0 for @records;
    }
  }

  # A composite primary key cannot be expressed as `id IN (...)`, and a readonly
  # record has to raise the way a single delete would, so both fall back to one
  # delete each.
  method !delete-many(@records) {
    if @records.grep({ .is-readonly || !.WHAT.default-id-locating }) {
      .delete for @records;
      return;
    }

    my @ids = self!linkable-ids(@records);
    return unless @ids.elems;

    my $table = Utils.table-name(@records[0]);
    my $slots = @ids.map({ '?' }).join(', ');

    self.db.exec-stmt(self.db.sanitize-sql-array([
      "DELETE FROM $table WHERE id IN ($slots)",
      |@ids,
    ]));

    for @records {
      .attrs<id>      = 0;
      .id             = 0;
      .is-destroyed   = True;
      .was-persisted  = True;
      .was-new-record = False;
    }
  }

  method !unlink-through-many(@records) {
    my $join-table = self!through-join-table;
    return unless $join-table;

    my @ids = self!linkable-ids(@records);
    return unless @ids.elems;

    my $owner-key  = self!through-owner-key;
    my $target-key = Utils.to-foreign-key($!assoc-name);
    my $slots      = @ids.map({ '?' }).join(', ');

    self.db.exec-stmt(self.db.sanitize-sql-array([
      "DELETE FROM $join-table WHERE $owner-key = ? AND $target-key IN ($slots)",
      self!owner-pkey-val, |@ids,
    ]));
  }

  method !nullify-fkey(Mu:D $record) {
    my $table = Utils.table-name($record);
    if self!is-polymorphic-as {
      my $as = self!as-name;
      my $id-col   = $as ~ '_id';
      my $type-col = $as ~ '_type';
      my $stmt = self.db.sanitize-sql-array([
        "UPDATE $table SET $id-col = NULL, $type-col = NULL WHERE id = ?",
        $record.id,
      ]);
      self.db.exec-stmt($stmt);
      $record.attrs{$id-col}   = 0;
      $record.attrs{$type-col} = '';
    } else {
      my $col = self!fkey-col;
      my $stmt = self.db.sanitize-sql-array([
        "UPDATE $table SET $col = NULL WHERE id = ?",
        $record.id,
      ]);
      self.db.exec-stmt($stmt);
      $record.attrs{$col} = 0;
    }
  }

  method !unlink-through(Mu:D $record) {
    my $join-table = self!through-join-table;
    return unless $join-table;
    my $owner-key  = self!through-owner-key;
    my $target-key = Utils.to-foreign-key($!assoc-name);
    self.db.delete-records(
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
    my $stmt = self.db.sanitize-sql-array([
      "INSERT INTO $join-table ($owner-key, $target-key) VALUES (?, ?)",
      self!owner-pkey-val, $record.id,
    ]);
    self.db.exec-stmt($stmt);
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
