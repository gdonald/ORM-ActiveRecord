
use ORM::ActiveRecord::Adapter;
use ORM::ActiveRecord::Support::Log;

role SqlExec is export {
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

  method exec(Str:D $sql, *@binds) {
    self!run-cached($sql, @binds, 'rows');
  }

  method exec-stmt(SqlStmt:D $stmt) {
    self!run-cached($stmt.sql, $stmt.binds, 'rows');
  }

  method exec-stmt-hash(SqlStmt:D $stmt) {
    self!run-cached($stmt.sql, $stmt.binds, 'hash');
  }

  method !run-cached(Str:D $sql, @binds, Str:D $format) {
    self.ensure-connected;
    self.check-write-allowed($sql);
    Log.sql(:$sql);

    self.clear-query-cache if self.is-write-sql($sql);

    if $!query-cache-enabled && self!is-cacheable-sql($sql) {
      my $key = self!query-cache-key($sql, @binds, $format);
      return %!query-cache{$key} if %!query-cache{$key}:exists;

      my @rows = self!run-statement($sql, @binds, $format);
      %!query-cache{$key} = @rows;

      return @rows;
    }

    self!run-statement($sql, @binds, $format);
  }

  method !run-statement(Str:D $sql, @binds, Str:D $format) {
    my $query = self!acquire-statement($sql);
    $query.execute(|@binds);
    my @rows = $format eq 'hash' ?? $query.allrows(:array-of-hash) !! $query.allrows;
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
