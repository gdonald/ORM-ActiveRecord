
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Log;

role SqlExec is export {
  method ensure-connected { self.connect unless self.db.defined }

  method exec(Str:D $sql, *@binds) {
    self.ensure-connected;
    Log.sql(:$sql);
    my $query = self.db.prepare($sql);
    $query.execute(|@binds);
    $query.allrows;
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self.ensure-connected;
    Log.sql(:sql($stmt.sql));
    my $query = self.db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    $query.allrows;
  }

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self.ensure-connected;
    Log.sql(:sql($stmt.sql));
    my $query = self.db.prepare($stmt.sql);
    $query.execute(|$stmt.binds);
    $query.allrows(:array-of-hash);
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
