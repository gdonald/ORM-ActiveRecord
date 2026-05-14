
role QueryConditions is export {
  method or-groups-payload {
    self.or-relations.map({
      %( where => $_.where-values, where-not => $_.where-not-values )
    });
  }

  method where(Hash:D $more = {}) {
    for self!normalize-assoc-params($more).kv -> $k, $v { self.where-values{$k} = $v }
    self;
  }

  method not(Hash:D $more) {
    for self!normalize-assoc-params($more).kv -> $k, $v { self.where-not-values{$k} = $v }
    self;
  }

  method rewhere(Hash:D $more) {
    for self!normalize-assoc-params($more).kv -> $k, $v {
      self.where-values{$k}:delete;
      self.where-not-values{$k}:delete;
      self.where-values{$k} = $v;
    }
    self;
  }

  method !normalize-assoc-params(Hash:D $h --> Hash) {
    my %out;
    my $stub = self.class-of.new(:id(0));
    for $h.kv -> $k, $v {
      if $stub.belongs-tos{$k}:exists {
        %out{$k ~ '_id'} = self!coerce-id-value($v);
      } else {
        %out{$k} = $v;
      }
    }
    %out;
  }

  method !coerce-id-value($v) {
    given $v {
      when Array | List | Seq {
        $v.list.map({ .defined && .^can('id') ?? .id !! $_ }).list;
      }
      default {
        $v.defined && $v.^can('id') ?? $v.id !! $v;
      }
    }
  }

  method excluding(*@records) {
    return self unless @records.elems;
    my @ids = @records.map({ .^can('id') ?? .id !! $_ });
    my %prev = self.where-not-values{'id'}:exists ?? %( id => self.where-not-values{'id'} ) !! %();
    if %prev<id>:exists {
      my @existing = %prev<id> ~~ Positional ?? %prev<id>.list !! (%prev<id>,);
      self.where-not-values{'id'} = (|@existing, |@ids).unique.list;
    } else {
      self.where-not-values{'id'} = @ids.list;
    }
    self;
  }

  method missing(*@names, *%kw) {
    my @all = @names.map(*.Str);
    for %kw.kv -> $k, $v { @all.push: $k if $v }
    die 'missing requires at least one association' unless @all.elems;
    for @all -> $assoc {
      my ($other-class, $other-table) = self.add-assoc-join('LEFT OUTER JOIN', $assoc, self.class-of, self.table-of);
      self.where-values{$other-table} //= {};
      self.where-values{$other-table}{'id'} = Any;
    }
    self;
  }

  method associated(*@names, *%kw) {
    my @all = @names.map(*.Str);
    for %kw.kv -> $k, $v { @all.push: $k if $v }
    die 'associated requires at least one association' unless @all.elems;
    for @all -> $assoc {
      self.add-assoc-join('INNER JOIN', $assoc, self.class-of, self.table-of);
    }
    self;
  }

  method or($other) {
    self.or-relations.push: $other;
    self;
  }

  method and($other) {
    for $other.where-values.kv -> $k, $v {
      self.where-not-values{$k}:delete;
      self.where-values{$k} = $v;
    }
    for $other.where-not-values.kv -> $k, $v {
      self.where-values{$k}:delete;
      self.where-not-values{$k} = $v;
    }
    self;
  }

  method merge($other) {
    for $other.where-values.kv -> $k, $v {
      self.where-not-values{$k}:delete;
      self.where-values{$k} = $v;
    }
    for $other.where-not-values.kv -> $k, $v {
      self.where-values{$k}:delete;
      self.where-not-values{$k} = $v;
    }
    self.order-values.append: $other.order-values if $other.order-values.elems;
    self.limit-value  = $other.limit-value  if $other.limit-value  > 0;
    self.offset-value = $other.offset-value if $other.offset-value > 0;
    self.select-values.append: $other.select-values if $other.select-values.elems;
    self.distinct-value = True if $other.distinct-value;
    self.group-values.append: $other.group-values if $other.group-values.elems;
    self.having-values.append: $other.having-values if $other.having-values.elems;
    if $other.from-source.defined {
      self.from-source = $other.from-source;
      self.from-alias  = $other.from-alias;
    }
    self.references-values.append: $other.references-values if $other.references-values.elems;
    self.readonly-value = True if $other.readonly-value;
    self.joins-values.append: $other.joins-values if $other.joins-values.elems;
    self.is-none-value = True if $other.is-none-value;
    for $other.create-with-attrs.kv -> $k, $v { self.create-with-attrs{$k} = $v }
    self.ctes-values.append: $other.ctes-values if $other.ctes-values.elems;
    self.annotations-values.append: $other.annotations-values if $other.annotations-values.elems;
    self.optimizer-hints-values.append: $other.optimizer-hints-values if $other.optimizer-hints-values.elems;
    self;
  }
}
