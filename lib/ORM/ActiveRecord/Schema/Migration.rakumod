
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

class ReversibleContext is export {
  has &.up-block   is rw;
  has &.down-block is rw;

  method up(&block)   { &!up-block   = &block }
  method down(&block) { &!down-block = &block }
}

class CommandRecorder {
  has @.commands;

  method record(Str:D $name, |capture) {
    @!commands.push: %(
      :$name,
      args => capture.list.cache,
      kw   => capture.hash,
    );
  }

  method inverse-commands {
    @!commands.reverse.map(-> %cmd { self!invert(%cmd) });
  }

  method !invert(%cmd) {
    given %cmd<name> {
      when 'create-table' {
        %( name => 'drop-table',
           args => [ %cmd<args>[0] ],
           kw   => {} );
      }
      when 'drop-table' {
        die X::IrreversibleMigration.new;
      }
      when 'create-join-table' {
        %( name => 'drop-join-table',
           args => %cmd<args>,
           kw   => %cmd<kw> );
      }
      when 'drop-join-table' {
        die X::IrreversibleMigration.new;
      }
      when 'add-column' {
        my $table = %cmd<args>[0];
        my $pair  = %cmd<args>[1];
        my $key   = $pair.key;
        my $col   = $key ~~ Pair ?? $key.key !! $key;

        %( name => 'remove-column',
           args => [ $table ],
           kw   => { $col => True } );
      }
      when 'remove-column' {
        die X::IrreversibleMigration.new;
      }
      when 'add-index' {
        %( name => 'remove-index',
           args => %cmd<args>,
           kw   => %cmd<kw> );
      }
      when 'remove-index' {
        die X::IrreversibleMigration.new;
      }
      when 'add-timestamps' {
        %( name => 'remove-timestamps',
           args => %cmd<args>,
           kw   => {} );
      }
      when 'remove-timestamps' {
        %( name => 'add-timestamps',
           args => %cmd<args>,
           kw   => {} );
      }
      when 'reversible' {
        %( name => 'run-block',
           args => [ %cmd<kw><down> ],
           kw   => {} );
      }
      when 'revert-block' {
        %( name => 'run-block',
           args => [ %cmd<kw><block> ],
           kw   => {} );
      }
      when 'execute' {
        die X::IrreversibleMigration.new;
      }
      when 'change-column' {
        die X::IrreversibleMigration.new;
      }
      when 'change-column-default' {
        my %kw = %cmd<kw>.hash;
        my @args = %cmd<args>.list;

        die X::IrreversibleMigration.new
          unless %kw<from>.defined && %kw<to>.defined;

        %( name => 'change-column-default',
           args => [ @args[0], @args[1] ],
           kw   => { from => %kw<to>, to => %kw<from> } );
      }
      when 'change-column-null' {
        my @args = %cmd<args>.list;
        my ($table, $name, $null) = @args[0], @args[1], @args[2];

        %( name => 'change-column-null',
           args => [ $table, $name, !$null ],
           kw   => {} );
      }
      when 'change-column-comment' {
        my %kw = %cmd<kw>.hash;
        my @args = %cmd<args>.list;

        die X::IrreversibleMigration.new
          unless %kw<from>.defined && %kw<to>.defined;

        %( name => 'change-column-comment',
           args => [ @args[0], @args[1] ],
           kw   => { from => %kw<to>, to => %kw<from> } );
      }
      when 'change-table-comment' {
        my %kw = %cmd<kw>.hash;
        my @args = %cmd<args>.list;

        die X::IrreversibleMigration.new
          unless %kw<from>.defined && %kw<to>.defined;

        %( name => 'change-table-comment',
           args => [ @args[0] ],
           kw   => { from => %kw<to>, to => %kw<from> } );
      }
      when 'rename-table' {
        my @args = %cmd<args>.list;
        %( name => 'rename-table',
           args => [ @args[1], @args[0] ],
           kw   => {} );
      }
      when 'rename-column' {
        my @args = %cmd<args>.list;
        %( name => 'rename-column',
           args => [ @args[0], @args[2], @args[1] ],
           kw   => {} );
      }
      when 'rename-index' {
        my @args = %cmd<args>.list;
        %( name => 'rename-index',
           args => [ @args[0], @args[2], @args[1] ],
           kw   => {} );
      }
      when 'add-reference' {
        my @args = %cmd<args>.list;
        %( name => 'remove-reference',
           args => @args,
           kw   => %cmd<kw> );
      }
      when 'remove-reference' {
        die X::IrreversibleMigration.new;
      }
      when 'add-foreign-key' {
        my @args = %cmd<args>.list;
        my %kw   = %cmd<kw>.hash;
        my %rm-kw;
        %rm-kw<column> = %kw<column> if %kw<column>:exists;
        %rm-kw<name>   = %kw<name>   if %kw<name>:exists;
        %( name => 'remove-foreign-key',
           args => [ @args[0] ],
           kw   => { :to-table(@args[1]), |%rm-kw } );
      }
      when 'remove-foreign-key' {
        die X::IrreversibleMigration.new;
      }
      when 'add-check-constraint' {
        my @args = %cmd<args>.list;
        my %kw   = %cmd<kw>.hash;
        my %rm-kw;
        %rm-kw<name> = %kw<name> if %kw<name>:exists;
        %rm-kw<expression> = @args[1] unless %kw<name>:exists;
        %( name => 'remove-check-constraint',
           args => [ @args[0] ],
           kw   => %rm-kw );
      }
      when 'remove-check-constraint' {
        die X::IrreversibleMigration.new;
      }
      when 'validate-check-constraint' {
        die X::IrreversibleMigration.new;
      }
      when 'add-unique-constraint' {
        my @args = %cmd<args>.list;
        my %kw   = %cmd<kw>.hash;
        my %rm-kw;
        %rm-kw<name>    = %kw<name>    if %kw<name>:exists;
        %rm-kw<columns> = %kw<columns> if %kw<columns>:exists;
        %( name => 'remove-unique-constraint',
           args => [ @args[0] ],
           kw   => %rm-kw );
      }
      when 'remove-unique-constraint' {
        die X::IrreversibleMigration.new;
      }
      when 'add-exclusion-constraint' {
        my @args = %cmd<args>.list;
        my %kw   = %cmd<kw>.hash;
        die X::IrreversibleMigration.new unless %kw<name>:exists;
        %( name => 'remove-exclusion-constraint',
           args => [ @args[0] ],
           kw   => { :name(%kw<name>) } );
      }
      when 'remove-exclusion-constraint' {
        die X::IrreversibleMigration.new;
      }
      default {
        die X::IrreversibleMigration.new;
      }
    }
  }
}

# Block-scoped builder yielded by `change-table`. Each call records an
# operation; the migration replays them (or coalesces the column ones into a
# single ALTER TABLE when :bulk is set).
class ChangeTableContext is export {
  has @.ops;

  method add-column(Pair:D $pair, *%opts) {
    @!ops.push: %( method => 'add-column', args => ($pair,), kw => %opts, coalesce => 'add', :$pair );
  }
  method column(Pair:D $pair, *%opts) { self.add-column($pair, |%opts) }

  method remove-column(Str:D $col, *%opts) {
    @!ops.push: %( method => 'remove-column', args => ($col,), kw => %opts, coalesce => 'drop', :$col );
  }
  method remove(Str:D $col, *%opts) { self.remove-column($col, |%opts) }

  method add-index(|c) {
    @!ops.push: %( method => 'add-index', args => c.list.cache, kw => c.hash, coalesce => Str );
  }
  method remove-index(|c) {
    @!ops.push: %( method => 'remove-index', args => c.list.cache, kw => c.hash, coalesce => Str );
  }
  method add-timestamps(*%opts) {
    @!ops.push: %( method => 'add-timestamps', args => (), kw => %opts, coalesce => Str );
  }
  method remove-timestamps(*%opts) {
    @!ops.push: %( method => 'remove-timestamps', args => (), kw => %opts, coalesce => Str );
  }
  method rename-column(Str:D $from, Str:D $to) {
    @!ops.push: %( method => 'rename-column', args => ($from, $to), kw => {}, coalesce => Str );
  }
  method add-reference(Str:D $name, *%opts) {
    @!ops.push: %( method => 'add-reference', args => ($name,), kw => %opts, coalesce => Str );
  }
  method add-belongs-to(Str:D $name, *%opts) { self.add-reference($name, |%opts) }
}

class Migration is export {
  has DB $!db;
  has Str $.direction is rw = 'up';
  has CommandRecorder $!recorder;

  submethod DESTROY {
    $!db = Nil;
  }

  submethod BUILD {
    $!db = DB.shared;
  }

  method up {
    $!direction = 'up';
    $!recorder  = Nil;

    self.change;
  }

  method down {
    $!direction = 'down';
    $!recorder  = CommandRecorder.new;

    self.change;

    my @inverse = $!recorder.inverse-commands;
    $!recorder = Nil;

    for @inverse -> %cmd {
      my @args = %cmd<args>.list;
      my %kw   = %cmd<kw>.hash;
      self."{%cmd<name>}"(|@args, |%kw);
    }
  }

  method change {
    die X::IrreversibleMigration.new;
  }

  method create-table(Str:D $table, @params, :$force, Bool :$temporary = False, Bool :$if-not-exists = False,
                      :$id = True, :$primary-key) {
    if $!recorder { $!recorder.record('create-table', $table, @params); return }

    $!db.ddl-create-table($table, @params, :$force, :$temporary, :$if-not-exists, :$id, :$primary-key);
  }

  method create-join-table(Str:D $table1, Str:D $table2, :$table-name, *%opts) {
    if $!recorder { $!recorder.record('create-join-table', $table1, $table2, :$table-name, |%opts); return }

    my $name = $table-name // self!join-table-name($table1, $table2);
    my ($col1, $col2) = self!join-columns($table1, $table2);

    $!db.ddl-create-join-table($name, $col1, $col2,
      |(null => %opts<null> with %opts<null>),
      |(type => %opts<type> with %opts<type>),
    );
  }

  method drop-join-table(Str:D $table1, Str:D $table2, :$table-name, *%opts) {
    if $!recorder { $!recorder.record('drop-join-table', $table1, $table2, :$table-name, |%opts); return }

    my $name = $table-name // self!join-table-name($table1, $table2);
    $!db.ddl-drop-join-table($name);
  }

  # Rails-style join-table name: the two table names sorted and joined with '_'.
  method !join-table-name(Str:D $t1, Str:D $t2 --> Str) {
    ($t1, $t2).sort.join('_');
  }

  # Foreign-key column names, in the order the tables were given.
  method !join-columns(Str:D $t1, Str:D $t2 --> List) {
    ($!db.ref-default-column($t1), $!db.ref-default-column($t2));
  }

  method table-exists(Str:D $table --> Bool) {
    so $!db.adapter.get-table-names.list.grep(* eq $table).elems;
  }

  method drop-table-if-exists(Str:D $table) {
    self.drop-table($table) if self.table-exists($table);
  }

  method drop-table(Str:D $table, Bool :$if-exists = False, Bool :$cascade = False) {
    if $!recorder { $!recorder.record('drop-table', $table); return }

    $!db.ddl-drop-table($table, :$if-exists, :$cascade);
  }

  method change-table(Str:D $table, &block, Bool :$bulk = False) {
    my $ctx = ChangeTableContext.new;
    block($ctx);

    # While recording a rollback, or when not coalescing, replay each op through
    # the public DSL so the recorder can invert them individually.
    if $!recorder || !$bulk {
      for $ctx.ops -> %op {
        self."{%op<method>}"($table, |%op<args>, |%op<kw>);
      }
      return;
    }

    # Bulk: fold ADD / DROP COLUMN into one ALTER TABLE; everything else
    # (indexes, renames, timestamps) runs as its own statement afterward.
    my @clauses;
    my @rest;

    for $ctx.ops -> %op {
      given %op<coalesce> {
        when 'add'  { @clauses.push("ADD COLUMN $_")  for $!db.ddl-column-defs(%op<pair>) }
        when 'drop' { @clauses.push("DROP COLUMN {%op<col>}") }
        default     { @rest.push(%op) }
      }
    }

    $!db.ddl-alter-table-bulk($table, @clauses) if @clauses;

    for @rest -> %op {
      self."{%op<method>}"($table, |%op<args>, |%op<kw>);
    }
  }

  method add-column(Str:D $table, Pair:D $params, *%opts) {
    if $!recorder { $!recorder.record('add-column', $table, $params); return }

    my Bool $if-not-exists = ?(%opts<if-not-exists>);
    $!db.ddl-add-column($table, $params, :$if-not-exists);
  }

  method remove-column(Str:D $table, |params) {
    if $!recorder { $!recorder.record('remove-column', $table, |params); return }

    my %named = params.hash;
    my Bool $if-exists = ?(%named<if-exists>:delete);
    my $field = params.list.first // %named.keys.first;

    $!db.ddl-remove-column($table, $field, :$if-exists);
  }

  method add-timestamps(Str:D $table) {
    if $!recorder { $!recorder.record('add-timestamps', $table); return }

    $!db.ddl-add-timestamps($table);
  }

  method remove-timestamps(Str:D $table) {
    if $!recorder { $!recorder.record('remove-timestamps', $table); return }

    $!db.ddl-remove-timestamps($table);
  }

  method add-index(Str:D $table, |params) {
    if $!recorder { $!recorder.record('add-index', $table, |params); return }

    my %spec = self!index-spec($table, params);

    $!db.ddl-add-index(
      $table,
      name       => %spec<name>,
      |(columns    => %spec<columns>    with %spec<columns>),
      unique     => %spec<unique>,
      |(expression => %spec<expression> with %spec<expression>),
      |(where      => %spec<where>      with %spec<where>),
      |(using      => %spec<using>      with %spec<using>),
      |(include    => %spec<include>    with %spec<include>),
      |(algorithm  => %spec<algorithm>  with %spec<algorithm>),
      |(if-not-exists => %spec<if-not-exists> with %spec<if-not-exists>),
    );
  }

  method remove-index(Str:D $table, |params) {
    if $!recorder { $!recorder.record('remove-index', $table, |params); return }

    my %spec = self!index-spec($table, params);

    $!db.ddl-remove-index(
      name => %spec<name>,
      :$table,
      |(algorithm => %spec<algorithm> with %spec<algorithm>),
      |(if-exists => %spec<if-exists> with %spec<if-exists>),
    );
  }

  # Normalize the many add-index / remove-index call shapes into one spec.
  #
  #   self.add-index: 'games', :year;
  #   self.add-index: 'clients', email => { :unique };
  #   self.add-index: 'subs', <user_id magazine_id> => { :unique };
  #   self.add-index: 'people', 'lower(email)', unique => True;
  #   self.add-index: 'logs', :level, where => 'level > 0', using => 'btree';
  #
  # Columns may arrive positionally (Str / List / Array, optionally as a
  # Pair carrying a per-column options hash) or, in the legacy adverb form,
  # as a named pair whose key is the column and whose value is True or an
  # options hash. Recognized option keys are pulled out by name.
  method !index-spec(Str:D $table, $captured) {
    my @optkeys = <unique name where using include algorithm opclass order expression if-not-exists if-exists>;

    my %named = $captured.hash;
    my %opts;

    for @optkeys -> $k {
      %opts{$k} = %named{$k}:delete if %named{$k}:exists;
    }

    my $cols;

    if %named.elems {
      my $ck  = %named.keys.first;
      my $val = %named{$ck};
      $cols = $ck;

      if $val ~~ Associative {
        for $val.kv -> $ok, $ov { %opts{$ok} //= $ov }
      }
    }

    my @pos = $captured.list;

    if @pos.elems {
      my $first = @pos[0];

      if $first ~~ Pair {
        $cols = $first.key;
        my $val = $first.value;

        if $val ~~ Associative {
          for $val.kv -> $ok, $ov { %opts{$ok} //= $ov }
        }
      }
      else {
        $cols = $first;
      }
    }

    my @columns = do given $cols {
      when List | Array { .list }
      when .defined     { ($cols,) }
      default           { () }
    };

    my $expression = %opts<expression>;
    my Bool $unique = ?%opts<unique>;

    my $name = %opts<name> // do {
      my $stem = $expression.defined
        ?? $!db.ref-expr-hash($expression)
        !! @columns.join('_');

      "{$table}_{$stem}_idx";
    };

    my $columns-body = @columns
      ?? @columns.map({ self!index-column-sql($_, %opts<opclass>, %opts<order>) }).join(', ')
      !! Str;

    %(
      :$name,
      columns    => $columns-body,
      :$unique,
      expression => $expression,
      where      => %opts<where>,
      using      => %opts<using>,
      include    => %opts<include>,
      algorithm  => %opts<algorithm>,
      if-not-exists => %opts<if-not-exists>,
      if-exists     => %opts<if-exists>,
    );
  }

  method !index-column-sql(Str:D $col, $opclass, $order --> Str) {
    my $oc  = self!index-col-opt($opclass, $col);
    my $ord = self!index-col-opt($order, $col);

    if $oc.defined {
      die "add-index: per-column opclass is not supported on this adapter"
        unless $!db.ref-index-supports-opclass;
    }

    my $sql = $col;
    $sql ~= " $oc"              if $oc.defined;
    $sql ~= ' ' ~ $ord.Str.uc  if $ord.defined;

    $sql;
  }

  method !index-col-opt($opt, Str:D $col) {
    return Nil without $opt;
    return $opt{$col} if $opt ~~ Associative;

    $opt;
  }

  method change-column(Str:D $table, Str:D $name, Str:D $type, *%opts) {
    if $!recorder {
      $!recorder.record('change-column', $table, $name, $type, |%opts);
      return;
    }

    $!db.ddl-change-column($table, $name, $type, |%opts);
  }

  method change-column-default(Str:D $table, Str:D $name, $value = Nil, :$from, :$to) {
    if $!recorder {
      $!recorder.record('change-column-default', $table, $name, $value, :$from, :$to);
      return;
    }

    my $new = ($from.defined && $to.defined) ?? $to !! $value;
    $!db.ddl-change-column-default($table, $name, $new);
  }

  method change-column-null(Str:D $table, Str:D $name, Bool:D $null, $default = Nil) {
    if $!recorder {
      $!recorder.record('change-column-null', $table, $name, $null, $default);
      return;
    }

    $!db.ddl-change-column-null($table, $name, $null, :$default);
  }

  method change-column-comment(Str:D $table, Str:D $name, $comment = Nil, :$from, :$to) {
    if $!recorder {
      $!recorder.record('change-column-comment', $table, $name, $comment, :$from, :$to);
      return;
    }

    my $new = ($from.defined && $to.defined) ?? $to !! $comment;
    $!db.ddl-change-column-comment($table, $name, $new);
  }

  method change-table-comment(Str:D $table, $comment = Nil, :$from, :$to) {
    if $!recorder {
      $!recorder.record('change-table-comment', $table, $comment, :$from, :$to);
      return;
    }

    my $new = ($from.defined && $to.defined) ?? $to !! $comment;
    $!db.ddl-change-table-comment($table, $new);
  }

  method rename-table(Str:D $from, Str:D $to) {
    if $!recorder { $!recorder.record('rename-table', $from, $to); return }

    $!db.ddl-rename-table($from, $to);
  }

  method rename-column(Str:D $table, Str:D $from, Str:D $to) {
    if $!recorder { $!recorder.record('rename-column', $table, $from, $to); return }

    $!db.ddl-rename-column($table, $from, $to);
  }

  method rename-index(Str:D $table, Str:D $from, Str:D $to) {
    if $!recorder { $!recorder.record('rename-index', $table, $from, $to); return }

    $!db.ddl-rename-index($table, $from, $to);
  }

  method add-reference(Str:D $table, Str:D $name, *%opts) {
    if $!recorder { $!recorder.record('add-reference', $table, $name, |%opts); return }

    $!db.ddl-add-reference($table, $name, |%opts);
  }

  method add-belongs-to(Str:D $table, Str:D $name, *%opts) {
    self.add-reference($table, $name, |%opts);
  }

  method remove-reference(Str:D $table, Str:D $name, *%opts) {
    if $!recorder { $!recorder.record('remove-reference', $table, $name, |%opts); return }

    $!db.ddl-remove-reference($table, $name, |%opts);
  }

  method remove-belongs-to(Str:D $table, Str:D $name, *%opts) {
    self.remove-reference($table, $name, |%opts);
  }

  method add-foreign-key(Str:D $from-table, Str:D $to-table, *%opts) {
    if $!recorder { $!recorder.record('add-foreign-key', $from-table, $to-table, |%opts); return }

    $!db.ddl-add-foreign-key($from-table, $to-table, |%opts);
  }

  method remove-foreign-key(Str:D $from-table, *%opts) {
    if $!recorder { $!recorder.record('remove-foreign-key', $from-table, |%opts); return }

    $!db.ddl-remove-foreign-key($from-table, |%opts);
  }

  method validate-foreign-key(Str:D $table, Str:D $name) {
    if $!recorder { $!recorder.record('validate-foreign-key', $table, $name); return }

    $!db.ddl-validate-foreign-key($table, $name);
  }

  method add-check-constraint(Str:D $table, Str:D $expression, *%opts) {
    if $!recorder { $!recorder.record('add-check-constraint', $table, $expression, |%opts); return }

    $!db.ddl-add-check-constraint($table, $expression, |%opts);
  }

  method remove-check-constraint(Str:D $table, *%opts) {
    if $!recorder { $!recorder.record('remove-check-constraint', $table, |%opts); return }

    $!db.ddl-remove-check-constraint($table, |%opts);
  }

  method validate-check-constraint(Str:D $table, Str:D $name) {
    if $!recorder { $!recorder.record('validate-check-constraint', $table, $name); return }

    $!db.ddl-validate-check-constraint($table, $name);
  }

  method add-unique-constraint(Str:D $table, *%opts) {
    if $!recorder { $!recorder.record('add-unique-constraint', $table, |%opts); return }

    $!db.ddl-add-unique-constraint($table, |%opts);
  }

  method remove-unique-constraint(Str:D $table, *%opts) {
    if $!recorder { $!recorder.record('remove-unique-constraint', $table, |%opts); return }

    $!db.ddl-remove-unique-constraint($table, |%opts);
  }

  method add-exclusion-constraint(Str:D $table, Str:D $expression, *%opts) {
    if $!recorder { $!recorder.record('add-exclusion-constraint', $table, $expression, |%opts); return }

    $!db.ddl-add-exclusion-constraint($table, $expression, |%opts);
  }

  method remove-exclusion-constraint(Str:D $table, *%opts) {
    if $!recorder { $!recorder.record('remove-exclusion-constraint', $table, |%opts); return }

    $!db.ddl-remove-exclusion-constraint($table, |%opts);
  }

  method execute(Str:D $sql) {
    if $!recorder { $!recorder.record('execute', $sql); return }

    $!db.exec($sql);
  }

  method reversible(&block) {
    my $ctx = ReversibleContext.new;
    block($ctx);

    if $!recorder {
      $!recorder.record('reversible', :down($ctx.down-block));
      return;
    }

    $ctx.up-block.() if $ctx.up-block.defined;
  }

  method revert(&block) {
    if $!recorder {
      $!recorder.record('revert-block', :block(&block));
      return;
    }

    $!recorder = CommandRecorder.new;
    block();
    my @inverse = $!recorder.inverse-commands;
    $!recorder = Nil;

    for @inverse -> %cmd {
      my @args = %cmd<args>.list;
      my %kw   = %cmd<kw>.hash;
      self."{%cmd<name>}"(|@args, |%kw);
    }
  }

  method run-block(&block) {
    block() if &block.defined;
  }

  method irreversible-migration {
    die X::IrreversibleMigration.new;
  }
}
