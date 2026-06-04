
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Log;

role SqlExec is export {
  method ensure-connected { self.connect unless self.db.defined }

  # Reify the rows, then let the adapter release the statement. SQLite resets
  # the statement so a leftover read lock can't block a later DROP TABLE; other
  # adapters leave statement teardown to GC (MySQL would leak prepared-statement
  # slots if reset here without a close).
  method release-statement($query) { }

  method exec(Str:D $sql, *@binds) {
    self.ensure-connected;
    self.check-write-allowed($sql);
    Log.sql(:$sql);
    my $query = self.db.prepare($sql);
    $query.execute(|@binds);
    my @rows = $query.allrows;
    self.release-statement($query);
    @rows;
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self.ensure-connected;
    self.check-write-allowed($stmt.sql);
    Log.sql(:sql($stmt.sql));
    my $query = self.db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    my @rows = $query.allrows;
    self.release-statement($query);
    @rows;
  }

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self.ensure-connected;
    self.check-write-allowed($stmt.sql);
    Log.sql(:sql($stmt.sql));
    my $query = self.db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    my @rows = $query.allrows(:array-of-hash);
    self.release-statement($query);
    @rows;
  }

  method explain(SqlStmt:D $stmt --> Str) {
    my $explain-stmt = SqlStmt.new(:adapter(self));
    $explain-stmt.sql = 'EXPLAIN ' ~ $stmt.sql;
    $explain-stmt.binds = $stmt.binds;
    my @rows = self.exec-stmt($explain-stmt);
    @rows.map({ $_.list.map(*.Str).join(' | ') }).join("\n");
  }

  method sanitize-sql-array(@parts --> SqlStmt) {
    SqlStmt.new(:adapter(self)).sanitize-array(@parts);
  }

  method sanitize-sql($input --> SqlStmt) {
    given $input {
      when SqlStmt    { $input }
      when Positional { self.sanitize-sql-array($input.list) }
      when Str        {
        my $stmt = SqlStmt.new(:adapter(self));
        $stmt.sql = $input;
        $stmt;
      }
      default { die 'sanitize-sql: unsupported input type ' ~ $input.^name }
    }
  }
}
