
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::DB;

role QuerySql is export {
  # Build this query's SELECT body into the given shared SqlStmt, returning
  # the SQL fragment. Used by adapters to emit CTE sub-queries that share
  # bind numbering with the outer SELECT.
  method to-sql-into(SqlStmt:D $stmt --> Str) {
    my @or-groups = self.or-groups-payload;
    DB.shared.build-select-body(
      $stmt,
      table => self.table-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values, limit => self.limit-value, offset => self.offset-value,
      distinct => self.distinct-value, group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      optimizer-hints => self.optimizer-hints-values,
    );
  }

  method to-sql(--> Str) {
    self.build-select-stmt.sql;
  }

  method explain(--> Str) {
    DB.shared.explain(self.build-select-stmt);
  }

  method build-select-stmt(--> SqlStmt) {
    my @or-groups = self.or-groups-payload;
    DB.shared.build-select(
      table => self.table-of, fields => self.fields-of,
      where => self.where-values, where-not => self.where-not-values, :@or-groups,
      order => self.order-values, limit => self.limit-value, offset => self.offset-value,
      distinct => self.distinct-value, group => self.group-values, having => self.having-values,
      from-source => self.from-source, from-alias => self.from-alias,
      joins => self.joins-values,
      ctes => self.ctes-values,
      annotations => self.annotations-values,
      optimizer-hints => self.optimizer-hints-values,
    );
  }

}
