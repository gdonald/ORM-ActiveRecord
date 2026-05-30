
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

  method create-table(Str:D $table, @params) {
    if $!recorder { $!recorder.record('create-table', $table, @params); return }

    $!db.ddl-create-table($table, @params);
  }

  method table-exists(Str:D $table --> Bool) {
    so $!db.adapter.get-table-names.list.grep(* eq $table).elems;
  }

  method drop-table-if-exists(Str:D $table) {
    self.drop-table($table) if self.table-exists($table);
  }

  method drop-table(Str:D $table) {
    if $!recorder { $!recorder.record('drop-table', $table); return }

    $!db.ddl-drop-table($table);
  }

  method add-column(Str:D $table, Pair:D $params) {
    if $!recorder { $!recorder.record('add-column', $table, $params); return }

    $!db.ddl-add-column($table, $params);
  }

  method remove-column(Str:D $table, |params) {
    if $!recorder { $!recorder.record('remove-column', $table, |params); return }

    my $field = params.keys.first;
    $!db.ddl-remove-column($table, $field);
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

    my $params = params;
    my $field = params.keys.first;
    my $name = $table ~ '_' ~ $field ~ '_idx';
    my Bool $unique = False;

    if !params{$field} {
      my ($keys, $values) = params[0].kv;

      if $keys ~~ List {
        $params = $values;
        $name = $table ~ '_' ~ $keys.join('_') ~ '_idx';
        $field = $keys.join(', ');
      }
    }

    for $params -> $param {
      given $param {
        when /:i unique/ { $unique = True }
        when .so {}
        default { say 'Unknown index param: ' ~ $param; die }
      }
    }

    $!db.ddl-add-index($table, :$name, columns => $field, :$unique);
  }

  method remove-index(Str:D $table, |params) {
    if $!recorder { $!recorder.record('remove-index', $table, |params); return }

    my $field = params.keys.first;
    my $name = $table ~ '_' ~ $field ~ '_idx';
    $!db.ddl-remove-index(:$name);
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
