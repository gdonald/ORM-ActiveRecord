
use ORM::ActiveRecord::Adapter;

role SqlAggregates is export {
  method count-records(Str:D :$table, :%where, :%where-not, :@or-groups, Bool:D :$distinct=False, :@select, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';
    my $hints = self.format-optimizer-hints(@optimizer-hints);
    my $hints-sp = $hints ?? " $hints" !! '';

    if @group.elems || @having.elems {
      my $inner = SqlStmt.new(:adapter(self));
      my $cte-prefix = self.build-ctes($inner, :@ctes);
      my $where-sql = self.build-where($inner, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
      my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
      my $group-clause = @group.elems ?? "GROUP BY @group.join(', ')" !! '';
      my $having-clause = self.build-having($inner, @having);
      my $body = qq:to/SQL/;
        SELECT count(*)$hints-sp FROM (
          SELECT 1 $from-clause
          $joins-sql
          $where-clause
          $group-clause
          $having-clause
        ) sub
        SQL
      my $annotated = self.attach-annotations($body, :@annotations);
      $inner.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;
      return self.exec-stmt($inner)[0][0].Int;
    }

    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';
    my $body;

    if $distinct {
      if @joins.elems && !@select.elems {
        $body = qq:to/SQL/;
          SELECT count(DISTINCT $qualifier.id)$hints-sp
          $from-clause
          $joins-sql
          $where-clause
          SQL
      } else {
        my $cols = @select.elems ?? @select.join(', ') !! '*';
        $body = qq:to/SQL/;
          SELECT count(*)$hints-sp
          FROM (
            SELECT DISTINCT $cols
            $from-clause
            $joins-sql
            $where-clause
          ) sub
          SQL
      }
    } else {
      $body = qq:to/SQL/;
        SELECT count(*)$hints-sp
        $from-clause
        $joins-sql
        $where-clause
        SQL
    }

    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;
    self.exec-stmt($stmt)[0][0].Int;
  }

  method aggregate(Str:D :$table, Str:D :$op, :$col is copy, :%where, :%where-not, :@or-groups, Bool:D :$distinct=False, :@group, :@having, Str :$from-source, Str :$from-alias, :@joins, :@ctes, :@annotations, :@optimizer-hints) {
    my $stmt = SqlStmt.new(:adapter(self));
    my $cte-prefix = self.build-ctes($stmt, :@ctes);
    my $hints = self.format-optimizer-hints(@optimizer-hints);
    my $qualifier = $from-alias.defined ?? $from-alias !! $table;
    my $from-clause = $from-source.defined ?? "FROM $from-source" !! "FROM $table";
    my $joins-sql = @joins.elems ?? @joins.join("\n") !! '';
    my $where-qualifier = @joins.elems ?? $qualifier !! Str;
    my $where-sql = self.build-where($stmt, %where, %where-not, :@or-groups, qualifier => $where-qualifier);
    my $where-clause = $where-sql ?? "WHERE $where-sql" !! '';

    my $needs-qualifier = @joins.elems.so;
    my $agg-col = self!agg-col-expr($op, $col, $distinct, $qualifier, $needs-qualifier);
    my $group-list = @group.map({ self!qualify-if-bare($_, $qualifier, $needs-qualifier) }).join(', ');
    my $group-clause = @group.elems ?? "GROUP BY $group-list" !! '';
    my $having-clause = self.build-having($stmt, @having);

    my $select-cols = @group.elems ?? "$group-list, $agg-col" !! $agg-col;
    my $select-keyword = $hints ?? "SELECT $hints" !! 'SELECT';

    my $body = qq:to/SQL/;
      $select-keyword $select-cols
      $from-clause
      $joins-sql
      $where-clause
      $group-clause
      $having-clause
      SQL
    my $annotated = self.attach-annotations($body, :@annotations);
    $stmt.sql = $cte-prefix ?? "$cte-prefix\n$annotated" !! $annotated;

    my @rows = self.exec-stmt($stmt);

    if @group.elems {
      my %result;
      my $gn = @group.elems;
      for @rows -> $row {
        my $key = $gn == 1 ?? $row[0] !! $row[0 ..^ $gn].List;
        %result{ $key } = self!coerce-agg-value($op, $row[$gn]);
      }
      return %result;
    }
    return self!agg-empty-default($op) unless @rows.elems;
    self!coerce-agg-value($op, @rows[0][0]);
  }

  method !agg-col-expr(Str:D $op, $col, Bool:D $distinct, Str:D $qualifier, Bool:D $needs-qualifier --> Str) {
    if $op eq 'COUNT' {
      return 'COUNT(*)' unless $col.defined && $col.Str.chars && $col.Str ne '*';
      my $c = self!qualify-if-bare($col.Str, $qualifier, $needs-qualifier);
      return $distinct ?? "COUNT(DISTINCT $c)" !! "COUNT($c)";
    }
    die "$op requires a column" unless $col.defined && $col.Str.chars;
    my $c = self!qualify-if-bare($col.Str, $qualifier, $needs-qualifier);
    $op ~ '(' ~ $c ~ ')';
  }

  method !qualify-if-bare(Str:D $name, Str:D $qualifier, Bool:D $needs-qualifier --> Str) {
    return $name unless $needs-qualifier;
    return $name if $name.contains('(') || $name.contains('.') || $name.contains(' ');
    "$qualifier.$name";
  }

  method !coerce-agg-value(Str:D $op, $value) {
    return self!agg-empty-default($op) without $value;
    given $op {
      when 'COUNT' { $value.Str.Int }
      when 'SUM' | 'AVG' {
        my $s = $value.Str;
        $s.contains('.') ?? $s.Rat !! $s.Int;
      }
      default { $value }
    }
  }

  method !agg-empty-default(Str:D $op) {
    given $op {
      when 'COUNT' { 0 }
      when 'SUM'   { 0 }
      default      { Nil }
    }
  }
}
