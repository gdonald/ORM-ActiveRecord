
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Support::Log;

role SqlTransactions is export {
  has Int $.txn-depth = 0;
  has Int $!sp-counter = 0;
  has @!txn-frames;

  method reset-txn-state {
    $!txn-depth = 0;
    $!sp-counter = 0;
    @!txn-frames = ();
  }

  method begin(Str :$isolation)    { self.begin-sql(:$isolation) }
  method commit   { self.txn-exec('COMMIT') }
  method rollback { self.txn-exec('ROLLBACK') }

  method is-in-transaction(--> Bool) { $!txn-depth > 0 }

  method begin-sql(Str :$isolation) {
    if $isolation.defined && $isolation.chars {
      my $clause = self.isolation-clause($isolation);
      self.txn-exec("BEGIN $clause");
    } else {
      self.txn-exec('BEGIN');
    }
  }

  method isolation-clause(Str:D $isolation --> Str) {
    'ISOLATION LEVEL ' ~ self.normalise-isolation($isolation);
  }

  method normalise-isolation(Str:D $iso --> Str) {
    my $u = $iso.uc.subst('_', ' ', :g).subst(/\s+/, ' ', :g).trim;
    given $u {
      when 'READ UNCOMMITTED' | 'READ COMMITTED' | 'REPEATABLE READ' | 'SERIALIZABLE' { $u }
      default { die "transaction: unknown isolation level '$iso'" }
    }
  }

  method savepoint(Str:D $name)             { self.txn-exec("SAVEPOINT $name") }
  method release-savepoint(Str:D $name)     { self.txn-exec("RELEASE SAVEPOINT $name") }
  method rollback-to-savepoint(Str:D $name) { self.txn-exec("ROLLBACK TO SAVEPOINT $name") }

  method transaction(&block, Bool:D :$requires-new = False, Str :$isolation) {
    if $isolation.defined && $isolation.chars {
      die "transaction: isolation level only applies to the outermost transaction"
        if $!txn-depth > 0;
      self.normalise-isolation($isolation);
    }

    if $!txn-depth == 0 {
      self.begin-sql(:$isolation);
      $!txn-depth = 1;
      $!sp-counter = 0;
      self!push-txn-frame;
      return self!run-outer(&block);
    }

    return self!run-joined(&block) unless $requires-new;

    my $name = self!next-savepoint;
    self.savepoint($name);
    $!txn-depth++;
    self!push-txn-frame;
    self!run-savepoint($name, &block);
  }

  method !run-outer(&block) {
    my $result;
    my $rolled-back = False;
    {
      CATCH {
        when X::Rollback {
          self.rollback;
          $!txn-depth = 0;
          $rolled-back = True;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
        }
        default {
          self.rollback;
          $!txn-depth = 0;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
          .rethrow;
        }
      }
      $result = block();
    }
    return Nil if $rolled-back;
    self.commit;
    $!txn-depth = 0;
    my $frame = self!pop-txn-frame;
    self!fire-commit-frame($frame);
    $result;
  }

  method !run-joined(&block) {
    block();
  }

  method !run-savepoint(Str:D $name, &block) {
    my $result;
    my $rolled-back = False;
    {
      CATCH {
        when X::Rollback {
          self.rollback-to-savepoint($name);
          self.release-savepoint($name);
          $!txn-depth--;
          $rolled-back = True;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
        }
        default {
          self.rollback-to-savepoint($name);
          self.release-savepoint($name);
          $!txn-depth--;
          my $frame = self!pop-txn-frame;
          self!fire-rollback-frame($frame);
          .rethrow;
        }
      }
      $result = block();
    }
    return Nil if $rolled-back;
    self.release-savepoint($name);
    $!txn-depth--;
    self!merge-txn-frame-into-parent;
    $result;
  }

  method !push-txn-frame { @!txn-frames.push: { records => {}, order => [] } }
  method !pop-txn-frame  { @!txn-frames.pop }

  method !merge-txn-frame-into-parent {
    my $top = @!txn-frames.pop;
    return unless @!txn-frames.elems;
    my $parent = @!txn-frames[*-1];
    for $top<order>.list -> $key {
      my %entry = $top<records>{$key};
      if $parent<records>{$key}:exists {
        for %entry<kinds>.keys -> $k {
          $parent<records>{$key}<kinds>{$k} = True;
        }
      } else {
        $parent<records>{$key} = %entry;
        $parent<order>.push: $key;
      }
    }
  }

  method register-txn-callback(Mu:D $record, Str:D $kind) {
    unless @!txn-frames.elems {
      self!fire-commit-record($record, %($kind => True));
      return;
    }
    my $key = $record.WHICH.Str;
    my $frame = @!txn-frames[*-1];
    unless $frame<records>{$key}:exists {
      $frame<records>{$key} = %(record => $record, kinds => {});
      $frame<order>.push: $key;
    }
    $frame<records>{$key}<kinds>{$kind} = True;
  }

  method !fire-commit-frame($frame) {
    return unless $frame.defined;
    for $frame<order>.list -> $key {
      my %entry = $frame<records>{$key};
      self!fire-commit-record(%entry<record>, %entry<kinds>);
    }
  }

  method !fire-rollback-frame($frame) {
    return unless $frame.defined;
    for $frame<order>.list -> $key {
      my %entry = $frame<records>{$key};
      self!fire-rollback-record(%entry<record>, %entry<kinds>);
    }
  }

  method !fire-commit-record(Mu:D $rec, %kinds) {
    return unless $rec.^can('run-after-commit');
    $rec.run-after-commit(:%kinds);
  }

  method !fire-rollback-record(Mu:D $rec, %kinds) {
    return unless $rec.^can('run-after-rollback');
    $rec.run-after-rollback(:%kinds);
  }

  method !next-savepoint(--> Str) {
    $!sp-counter++;
    'ar_sp_' ~ $!sp-counter;
  }

  # DBDish::mysql rejects transaction-control statements via prepare(),
  # so callers must use this path instead of exec() for BEGIN / COMMIT /
  # ROLLBACK / SAVEPOINT / SET TRANSACTION.
  method txn-exec(Str:D $sql) {
    self.ensure-connected;
    Log.sql(:$sql);
    self.db.execute($sql);
  }
}
