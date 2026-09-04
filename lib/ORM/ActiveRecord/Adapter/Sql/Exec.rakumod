
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

  # Recency as an intrusive doubly-linked list over the cache keys, so a hit
  # relinks in constant time. Rebuilding a list of the SQL texts on every hit
  # made a hit cost as much as the cache is large.
  has      %!lru-prev;    # sql => the sql used just before it
  has      %!lru-next;    # sql => the sql used just after it
  has Str  $!lru-newest;
  has Str  $!lru-oldest;

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
  #
  # A statement carrying a query-log comment is not cached: the comment varies
  # per controller and action, so every execution is a fresh SQL text. Caching
  # those would fill the cache with entries nothing ever hits and evict the
  # ones that are hit.
  method !acquire-statement(Str:D $sql, Bool :$cacheable = True) {
    return self.db.prepare($sql) unless $cacheable;

    if %!stmt-cache{$sql}:exists {
      self!lru-touch($sql);
      return %!stmt-cache{$sql};
    }

    my $query = self.db.prepare($sql);

    %!stmt-cache{$sql} = $query;
    self!lru-touch($sql);
    self!evict-statements;

    $query;
  }

  method !lru-touch(Str:D $sql) {
    self!lru-unlink($sql);

    %!lru-prev{$sql} = Str;
    %!lru-next{$sql} = $!lru-newest;
    %!lru-prev{$!lru-newest} = $sql if $!lru-newest.defined;
    $!lru-newest = $sql;
    $!lru-oldest //= $sql;
  }

  method !lru-unlink(Str:D $sql) {
    return unless (%!lru-next{$sql}:exists) || (%!lru-prev{$sql}:exists);

    my $prev = %!lru-prev{$sql};
    my $next = %!lru-next{$sql};

    $prev.defined ?? (%!lru-next{$prev} = $next) !! ($!lru-newest = $next);
    $next.defined ?? (%!lru-prev{$next} = $prev) !! ($!lru-oldest = $prev);

    %!lru-prev{$sql}:delete;
    %!lru-next{$sql}:delete;
  }

  method !lru-clear {
    %!lru-prev  = ();
    %!lru-next  = ();
    $!lru-newest = Str;
    $!lru-oldest = Str;
  }

  method !finish-statement($query, Bool :$cacheable = True) {
    $cacheable ?? $query.finish !! self.release-statement($query);
  }

  method !evict-statements {
    while %!stmt-cache.elems > $!prepared-statement-cache-size && $!lru-oldest.defined {
      my $sql = $!lru-oldest;
      self!lru-unlink($sql);
      (%!stmt-cache{$sql}:delete).dispose;
    }
  }

  method clear-statement-cache {
    .dispose for %!stmt-cache.values;

    %!stmt-cache = ();
    self!lru-clear;
  }

  method cached-statement-count(--> Int) { %!stmt-cache.elems }

  # Per-request query cache. When enabled, the rows from a read statement are
  # memoized by SQL + binds + result shape, so repeating the same query inside
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

  method !is-cacheable-stripped(Str:D $stripped --> Bool) {
    return False if self.is-write-stripped($stripped);
    so $stripped ~~ /^ :i (select | with) <|w> /;
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

  # Hand each row to the block as the driver produces it, so a result set larger
  # than memory can be read. `exec-stmt` and the relation finders reify every
  # row before returning, which is what makes them safe to hand around; this
  # keeps the connection locked and the statement open for the life of the
  # iteration instead, so the block must not run another statement on this
  # connection. Nothing is cached, since holding the rows is the thing being
  # avoided. Returns the number of rows handed over.
  method stream-stmt(SqlStmt:D $stmt, &block, Bool :$hash = False --> Int) {
    self.serialized: {
      self.ensure-connected;

      my $sql      = $stmt.sql;
      my $stripped = self.strip-sql-prefix($sql);

      self.check-write-allowed($sql, :is-write(self.is-write-stripped($stripped)));
      Log.sql(:$sql);

      my $exec-sql = QueryLogs.annotate($sql);
      my $query    = self!acquire-statement($exec-sql, :cacheable(False));

      LEAVE self.release-statement($query);

      $query.execute(|$stmt.binds);

      my Int $count = 0;

      loop {
        my $row = $query.row(:$hash);
        last unless $row.elems;

        block($row);
        $count++;
      }

      $count;
    }
  }

  method !run-cached(Str:D $sql, @binds, Str:D $format) {
    self.ensure-connected;

    # Classified once here. `check-write-allowed`, the query-cache guard, the
    # schema-cache guard, the cacheability test, and the instrumentation name
    # each used to strip the comments and leading whitespace again on their way
    # to their own match.
    my $stripped = self.strip-sql-prefix($sql);
    my $is-write = self.is-write-stripped($stripped);

    self.check-write-allowed($sql, :$is-write);
    Log.sql(:$sql);

    self.clear-query-cache if $is-write;
    self.clear-schema-cache if self.is-schema-change-stripped($stripped);

    if $!query-cache-enabled && self!is-cacheable-stripped($stripped) {
      my $key = self!query-cache-key($sql, @binds, $format);

      if %!query-cache{$key}:exists {
        my @cached = %!query-cache{$key};

        if Notifications.has-subscribers('sql.active_record') {
          Notifications.notify('sql.active_record',
            { :$sql, binds => @binds.List, cached => True, name => self!sql-name($stripped), duration => 0e0 });
        }

        return @cached;
      }

      my @rows = self!run-statement($sql, @binds, $format, $stripped);
      %!query-cache{$key} = @rows;

      return @rows;
    }

    self!run-statement($sql, @binds, $format, $stripped);
  }

  # Execute a statement, recovering transparently from a dropped connection. A
  # server restart or a reaped idle socket makes the next statement fail; when
  # that happens outside a transaction, reconnect so later requests work and
  # replay the statement if it is a read. A write is surfaced rather than
  # replayed, since it may have partially applied. A statement that fails while
  # the connection still answers is a genuine SQL error and is re-thrown as-is.
  method !run-statement(Str:D $sql, @binds, Str:D $format, Str:D $stripped) {
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
        $error.rethrow unless self!replayable-read($stripped);
        return self!run-statement-once($sql, @binds, $format, $stripped);
      }
    }

    return self!run-statement-once($sql, @binds, $format, $stripped);
  }

  # The raw single execution: acquire a statement, run it, reify the rows, and
  # dispose. Never attempts connection recovery, so the probe and the replay
  # above can call it without re-entering the recovery wrapper.
  method !run-statement-once(Str:D $sql, @binds, Str:D $format, Str:D $stripped) {
    my $exec-sql  = QueryLogs.annotate($sql);
    my $cacheable = $!prepared-statements && $exec-sql eq $sql;

    my &run = {
      my $query = self!acquire-statement($exec-sql, :$cacheable);
      $query.execute(|@binds);
      my @rows = $format eq 'hash' ?? $query.allrows(:array-of-hash) !! $query.allrows;
      self!finish-statement($query, :$cacheable);

      @rows;
    };

    # The payload is built only when something consumes it. With no subscriber
    # `instrument` throws the hash, the bind list, and the statement name away
    # immediately, and that is the common case.
    return run() unless Notifications.has-subscribers('sql.active_record');

    Notifications.instrument('sql.active_record',
      { sql => $exec-sql, binds => @binds.List, cached => False, name => self!sql-name($stripped) },
      &run);
  }

  # Liveness probe that bypasses the recovery wrapper. False on a dropped or
  # dead connection, and never throws.
  method !connection-alive(--> Bool) {
    return False unless self.is-connected;
    (try { self!run-statement-once('SELECT 1', [], 'rows', 'SELECT 1'); True }) // False;
  }

  # A SELECT / WITH read is safe to replay after a reconnect; anything else is
  # left to the caller.
  method !replayable-read(Str:D $stripped --> Bool) {
    so $stripped ~~ /^ :i (select | with) <|w> /;
  }

  method !sql-name(Str:D $stripped --> Str) {
    ($stripped ~~ /^ (\w+) /) ?? $0.Str.uc !! 'SQL';
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
