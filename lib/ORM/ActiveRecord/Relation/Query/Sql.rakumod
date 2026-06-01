
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::DB;

role QuerySql is export {
  # Shares bind numbering with $stmt so CTE sub-queries don't re-start at $1.
  method to-sql-into(SqlStmt:D $stmt --> Str) {
    self.finalize-includes;
    my @or-groups = self.or-groups-payload;
    self.db.build-select-body(
      $stmt,
      table => self.table-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values, limit => self.limit-value, offset => self.offset-value,
      distinct => self.distinct-value, group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
  }

  method to-sql(--> Str) {
    self.build-select-stmt.sql;
  }

  method explain(--> Str) {
    self.db.explain(self.build-select-stmt);
  }

  method build-select-stmt(--> SqlStmt) {
    self.finalize-includes;
    my @or-groups = self.or-groups-payload;
    self.db.build-select(
      table => self.table-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values, limit => self.limit-value, offset => self.offset-value,
      distinct => self.distinct-value, group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
      lock => self.lock-value,
    );
  }
}
