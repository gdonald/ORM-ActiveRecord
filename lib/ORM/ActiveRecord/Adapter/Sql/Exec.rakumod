
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Log;

role SqlExec is export {
  has Bool $.prepared-statements is rw = False;
  has Int  $.prepared-statement-cache-size is rw = 1000;
  has      %!stmt-cache;
  has      @!stmt-lru;

  method ensure-connected { self.connect unless self.db.defined }

  # Reify the rows, then dispose the statement immediately rather than leaving
  # it to GC. This finalizes it on every driver: SQLite releases the read lock
  # that would otherwise block a later DROP TABLE, and MySQL closes the
  # server-side prepared statement so a long run can't exhaust
  # max_prepared_stmt_count.
  method release-statement($query) { $query.dispose }

  # When prepared statements are enabled, a prepared handle is reused across
  # calls keyed by its SQL text. A cached handle is reset (finish) after each
  # use, which releases the SQLite read lock and resets MySQL result state
  # while leaving it ready to re-execute with fresh binds. The cache is bounded
  # by prepared-statement-cache-size and evicts least-recently-used handles.
  method !acquire-statement(Str:D $sql) {
    return self.db.prepare($sql) unless $!prepared-statements;

    if %!stmt-cache{$sql}:exists {
      @!stmt-lru = @!stmt-lru.grep(* ne $sql);
      @!stmt-lru.push($sql);

      return %!stmt-cache{$sql};
    }

    my $query = self.db.prepare($sql);

    %!stmt-cache{$sql} = $query;
    @!stmt-lru.push($sql);
    self!evict-statements;

    $query;
  }

  method !finish-statement($query) {
    $!prepared-statements ?? $query.finish !! self.release-statement($query);
  }

  method !evict-statements {
    while @!stmt-lru.elems > $!prepared-statement-cache-size {
      my $sql = @!stmt-lru.shift;
      (%!stmt-cache{$sql}:delete).dispose;
    }
  }

  method clear-statement-cache {
    .dispose for %!stmt-cache.values;

    %!stmt-cache = ();
    @!stmt-lru  = ();
  }

  method cached-statement-count(--> Int) { %!stmt-cache.elems }

  method exec(Str:D $sql, *@binds) {
    self.ensure-connected;
    self.check-write-allowed($sql);
    Log.sql(:$sql);

    my $query = self!acquire-statement($sql);
    $query.execute(|@binds);
    my @rows = $query.allrows;
    self!finish-statement($query);

    @rows;
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self.ensure-connected;
    self.check-write-allowed($stmt.sql);
    Log.sql(:sql($stmt.sql));

    my $query = self!acquire-statement($stmt.sql);
    $query.execute(|$stmt.binds);
    my @rows = $query.allrows;
    self!finish-statement($query);

    @rows;
  }

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self.ensure-connected;
    self.check-write-allowed($stmt.sql);
    Log.sql(:sql($stmt.sql));

    my $query = self!acquire-statement($stmt.sql);
    $query.execute(|$stmt.binds);
    my @rows = $query.allrows(:array-of-hash);
    self!finish-statement($query);

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
