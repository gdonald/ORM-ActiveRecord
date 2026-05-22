
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;

role QueryFinders is export {
  method perform {
    return () if self.is-none-value;
    self.finalize-includes;
    my @or-groups = self.or-groups-payload;
    my @objects = DB.shared.get-objects(
      table => self.table-of, class => self.class-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values,
      limit => self.limit-value, offset => self.offset-value,
      distinct => self.distinct-value,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
    if self.readonly-value {
      .make-readonly for @objects;
    }
    self.apply-preloads(@objects);
    @objects;
  }

  method all {
    self.perform;
  }

  multi method first {
    return Any if self.is-none-value;
    self.finalize-includes;
    my @order = self.order-values.elems ?? self.order-values !! ('id',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(table => self.table-of, class => self.class-of, fields => self.fields-of, where => self.where-values, where-not => self.where-not-values, :@or-groups, :@order, distinct => self.distinct-value, group => self.group-values, having => self.having-values, from-source => self.from-source, from-alias => self.from-alias, joins => self.joins-values, ctes => self.ctes-values, annotations => self.annotations-values, optimizer-hints => self.optimizer-hints-values, lock => self.lock-value);
    $obj.make-readonly if $obj.defined && self.readonly-value;
    $obj;
  }

  multi method first(Int:D $n) {
    return () if self.is-none-value;
    die "first($n): N must be >= 0" if $n < 0;
    return () if $n == 0;
    self.finalize-includes;
    my @order = self.order-values.elems ?? self.order-values !! ('id',);
    my @or-groups = self.or-groups-payload;
    my @objects = DB.shared.get-objects(
      table => self.table-of, class => self.class-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      :@order, limit => $n, offset => self.offset-value,
      distinct => self.distinct-value,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
    if self.readonly-value {
      .make-readonly for @objects;
    }
    @objects;
  }

  multi method last {
    return Any if self.is-none-value;
    self.finalize-includes;
    my @order = self.order-values.elems
      ?? self.order-values
      !! ('id DESC',);
    my @or-groups = self.or-groups-payload;
    my $obj = DB.shared.get-object(table => self.table-of, class => self.class-of, fields => self.fields-of, where => self.where-values, where-not => self.where-not-values, :@or-groups, :@order, distinct => self.distinct-value, group => self.group-values, having => self.having-values, from-source => self.from-source, from-alias => self.from-alias, joins => self.joins-values, ctes => self.ctes-values, annotations => self.annotations-values, optimizer-hints => self.optimizer-hints-values, lock => self.lock-value);
    $obj.make-readonly if $obj.defined && self.readonly-value;
    $obj;
  }

  multi method last(Int:D $n) {
    return () if self.is-none-value;
    die "last($n): N must be >= 0" if $n < 0;
    return () if $n == 0;
    self.finalize-includes;
    my @order = self.order-values.elems
      ?? self.order-values.map({ self!reverse-order-fragment($_) })
      !! ('id DESC',);
    my @or-groups = self.or-groups-payload;
    my @objects = DB.shared.get-objects(
      table => self.table-of, class => self.class-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      :@order, limit => $n, offset => self.offset-value,
      distinct => self.distinct-value,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
    if self.readonly-value {
      .make-readonly for @objects;
    }
    @objects.reverse;
  }

  method !reverse-order-fragment($frag) {
    given $frag {
      when Str {
        if $frag.uc.contains(' DESC') { $frag.subst(/:i ' DESC' \s* $/, ' ASC') }
        elsif $frag.uc.contains(' ASC') { $frag.subst(/:i ' ASC' \s* $/, ' DESC') }
        else { $frag ~ ' DESC' }
      }
      default { $frag }
    }
  }

  method sole {
    die X::RecordNotFound.new(:model(self.class-of.^name)) if self.is-none-value;
    self.finalize-includes;
    my @or-groups = self.or-groups-payload;
    my @rows = DB.shared.get-objects(
      table => self.table-of, class => self.class-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values,
      limit => 2, offset => self.offset-value,
      distinct => self.distinct-value,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
    die X::RecordNotFound.new(:model(self.class-of.^name)) unless @rows.elems;
    die X::SoleRecordExceeded.new(:model(self.class-of.^name)) if @rows.elems > 1;
    my $obj = @rows[0];
    $obj.make-readonly if self.readonly-value;
    $obj;
  }

  method pluck(*@cols) {
    return () if self.is-none-value;
    self.finalize-includes;
    my @names = @cols.elems ?? @cols.map({ .Str }) !! self.select-values.elems ?? self.select-values !! die 'pluck requires at least one column';
    my @fields = @names.map({ Field.new(:name($_), :type('character varying')) });
    my @or-groups = self.or-groups-payload;
    my @rows = DB.shared.exec-stmt(
      DB.shared.build-select(
        table => self.table-of, :@fields, where => self.where-values, where-not => self.where-not-values, :@or-groups,
        order => self.order-values, limit => self.limit-value, offset => self.offset-value,
        distinct => self.distinct-value,
        group => self.group-values, having => self.having-values,
        from-source => self.from-source, from-alias => self.from-alias,
        joins => self.joins-values,
        ctes => self.ctes-values,
        annotations => self.annotations-values,
        optimizer-hints => self.optimizer-hints-values,
        lock => self.lock-value,
      )
    );
    if @names.elems == 1 {
      @rows.map({ $_[0] });
    } else {
      @rows.map({ $_.list });
    }
  }

  method ids {
    self.pluck('id').map({ .Int });
  }

  method pick(*@cols) {
    return Any if self.is-none-value;
    my @names = @cols.elems ?? @cols.map({ .Str }) !! die 'pick requires at least one column';
    my $prev-limit = self.limit-value;
    self.limit-value = 1;
    my @rows = self.pluck(|@names);
    self.limit-value = $prev-limit;
    return Any unless @rows.elems;
    @rows[0];
  }

  method !build-attrs-for-create(Hash:D $params --> Hash) {
    my %attrs;
    for self.where-values.kv -> $k, $v {
      next if $v ~~ Array | List | Seq | Range;
      next unless $v.defined;
      %attrs{$k} = $v;
    }
    for self.create-with-attrs.kv -> $k, $v { %attrs{$k} = $v }
    for $params.kv -> $k, $v { %attrs{$k} = $v }
    %attrs;
  }

  method !find-with-params(Hash:D $params) {
    my %saved-params = %( self.where-values );
    self.where($params);
    my $obj = self.first;
    self.where-values = %saved-params;
    $obj;
  }

  method find-or-create-by(Hash:D $params) {
    my $obj = self!find-with-params($params);
    return $obj if $obj.defined;
    self.class-of.create(self!build-attrs-for-create($params));
  }

  method find-or-create-by-or-die(Hash:D $params) {
    my $obj = self!find-with-params($params);
    return $obj if $obj.defined;
    self.class-of.create-or-die(self!build-attrs-for-create($params));
  }

  method find-or-initialize-by(Hash:D $params) {
    my $obj = self!find-with-params($params);
    return $obj if $obj.defined;
    self.class-of.build(self!build-attrs-for-create($params));
  }
}
