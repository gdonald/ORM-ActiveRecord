
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Log;
use ORM::ActiveRecord::Instrumentation::Notifications;
use ORM::ActiveRecord::Instrumentation::QueryLogs;

role SqlExec is export {
  # A connection is a single protocol stream: two threads interleaving
  # statements on it desync the wire (libpq reports "message type 0x..
  # arrived from server while idle") and every later call blocks forever in
  # the driver. Pooled connections are single-user, so this lock is
  # uncontended there; the shared fallback connection is reachable from any
  # thread and needs it. Lock is reentrant, so a transaction block holding it
  # can still run its own statements.
  has Lock $!serial-lock = Lock.new;

  has Bool $.prepared-statements is rw = False;
  has Int  $.prepared-statement-cache-size is rw = 1000;
  has      %!stmt-cache;
  has      @!stmt-lru;

  has Bool $!query-cache-enabled = False;
  has      %!query-cache;

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

  # Per-request query cache. When enabled, the rows from a read statement are
  # memoised by SQL + binds + result shape, so repeating the same query inside
  # the cache window skips the database. Any write clears the cache (even when
  # caching is disabled) so a later read can't serve stale rows.
  method query-cache-enabled(--> Bool) { $!query-cache-enabled }
  method cached-query-count(--> Int)   { %!query-cache.elems }

  method enable-query-cache  { $!query-cache-enabled = True }
  method disable-query-cache { $!query-cache-enabled = False; self.clear-query-cache }
  method clear-query-cache   { %!query-cache = () }

  method cache(&block) {
    my $was = $!query-cache-enabled;
    $!query-cache-enabled = True;
    LEAVE { $!query-cache-enabled = $was; self.clear-query-cache unless $was }
    block();
  }

  method uncached(&block) {
    my $was = $!query-cache-enabled;
    $!query-cache-enabled = False;
    LEAVE $!query-cache-enabled = $was;
    block();
  }

  method !is-cacheable-sql(Str:D $sql --> Bool) {
    return False if self.is-write-sql($sql);
    so $sql.subst(/^ \s+ /, '') ~~ /^ :i (select | with) <|w> /;
  }

  method !query-cache-key(Str:D $sql, @binds, Str:D $format --> Str) {
    ($format, $sql, |@binds.map({ .defined ?? .Str !! "\x[0]" })).join("\x[1]");
  }

  # Serialize a block against this adapter's connection.
  method serialized(&block) {
    $!serial-lock.protect(&block);
  }

  method exec(Str:D $sql, *@binds) {
    self.serialized: { self!run-cached($sql, @binds, 'rows') }
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self.serialized: { self!run-cached($stmt.sql, $stmt.binds, 'rows') }
  }

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self.serialized: { self!run-cached($stmt.sql, $stmt.binds, 'hash') }
  }

  method !run-cached(Str:D $sql, @binds, Str:D $format) {
    self.ensure-connected;
    self.check-write-allowed($sql);
    Log.sql(:$sql);

    self.clear-query-cache if self.is-write-sql($sql);
    self.clear-schema-cache if self.is-schema-change-sql($sql);

    if $!query-cache-enabled && self!is-cacheable-sql($sql) {
      my $key = self!query-cache-key($sql, @binds, $format);

      if %!query-cache{$key}:exists {
        my @cached = %!query-cache{$key};
        Notifications.notify('sql.active_record',
          { :$sql, binds => @binds.List, cached => True, name => self!sql-name($sql), duration => 0e0 });
        return @cached;
      }

      my @rows = self!run-statement($sql, @binds, $format);
      %!query-cache{$key} = @rows;

      return @rows;
    }

    self!run-statement($sql, @binds, $format);
  }

  # Execute a statement, recovering transparently from a dropped connection. A
  # server restart or a reaped idle socket makes the next statement fail; when
  # that happens outside a transaction, reconnect so later requests work and
  # replay the statement if it is a read. A write is surfaced rather than
  # replayed, since it may have partially applied. A statement that fails while
  # the connection still answers is a genuine SQL error and is re-thrown as-is.
  method !run-statement(Str:D $sql, @binds, Str:D $format) {
    CATCH {
      default {
        my $error = $_;

        # Inside a transaction the transaction is already lost, so there is
        # nothing to salvage here; let the transaction manager roll back.
        $error.rethrow if self.is-in-transaction;

        # If the connection still answers, the SQL itself failed.
        $error.rethrow if self!connection-alive;

        # The connection dropped. Reconnect for the next caller, and replay this
        # statement only if it is a read.
        self.reconnect;
        $error.rethrow unless self!replayable-read($sql);
        return self!run-statement-once($sql, @binds, $format);
      }
    }

    return self!run-statement-once($sql, @binds, $format);
  }

  # The raw single execution: acquire a statement, run it, reify the rows, and
  # dispose. Never attempts connection recovery, so the probe and the replay
  # above can call it without re-entering the recovery wrapper.
  method !run-statement-once(Str:D $sql, @binds, Str:D $format) {
    my $exec-sql = QueryLogs.annotate($sql);

    Notifications.instrument('sql.active_record',
      { sql => $exec-sql, binds => @binds.List, cached => False, name => self!sql-name($sql) },
      {
        my $query = self!acquire-statement($exec-sql);
        $query.execute(|@binds);
        my @rows = $format eq 'hash' ?? $query.allrows(:array-of-hash) !! $query.allrows;
        self!finish-statement($query);

        @rows;
      });
  }

  # Liveness probe that bypasses the recovery wrapper. False on a dropped or
  # dead connection, and never throws.
  method !connection-alive(--> Bool) {
    return False unless self.is-connected;
    (try { self!run-statement-once('SELECT 1', [], 'rows'); True }) // False;
  }

  # A SELECT / WITH read is safe to replay after a reconnect; anything else is
  # left to the caller.
  method !replayable-read(Str:D $sql --> Bool) {
    so $sql.subst(/^ \s+ /, '') ~~ /^ :i (select | with) <|w> /;
  }

  method !sql-name(Str:D $sql --> Str) {
    ($sql.subst(/^ \s+ /, '') ~~ /^ (\w+) /) ?? $0.Str.uc !! 'SQL';
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
