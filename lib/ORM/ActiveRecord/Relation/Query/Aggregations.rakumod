
use ORM::ActiveRecord::DB;

role QueryAggregations is export {
  multi method count() {
    self!do-count(Any);
  }

  multi method count($col) {
    self!do-count($col);
  }

  method !do-count($col) {
    return self.group-values.elems ?? %() !! 0 if self.is-none-value;
    self.finalize-includes;
    if self.group-values.elems || ($col.defined && $col !~~ '*') {
      return self!aggregate('COUNT', $col);
    }
    my @or-groups = self.or-groups-payload;
    DB.shared.count-records(
      table => self.table-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      distinct => self.distinct-value, select => self.select-values,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
    );
  }

  method sum($col)     { self!agg-with-none('SUM',     $col, 0)   }
  method average($col) { self!agg-with-none('AVG',     $col, Nil) }
  method minimum($col) { self!agg-with-none('MIN',     $col, Nil) }
  method maximum($col) { self!agg-with-none('MAX',     $col, Nil) }

  method calculate(Str:D $op, $col?) {
    given $op.lc {
      when 'sum'                 { self.sum($col)     }
      when 'avg' | 'average'     { self.average($col) }
      when 'min' | 'minimum'     { self.minimum($col) }
      when 'max' | 'maximum'     { self.maximum($col) }
      when 'count'               { self.count($col)   }
      default { die "calculate: unknown operation '$op'" }
    }
  }

  method !agg-with-none(Str:D $op, $col, $empty) {
    return self.group-values.elems ?? %() !! $empty if self.is-none-value;
    self!aggregate($op, $col);
  }

  method !aggregate(Str:D $op, $col) {
    self.finalize-includes;
    my @or-groups = self.or-groups-payload;
    DB.shared.aggregate(
      table => self.table-of, :$op, :$col,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      distinct => self.distinct-value,
      group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
    );
  }
}
