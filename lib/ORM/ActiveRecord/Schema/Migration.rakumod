
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
