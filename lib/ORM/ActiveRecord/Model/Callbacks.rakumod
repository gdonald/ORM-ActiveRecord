
use ORM::ActiveRecord::Errors::X;

class CallbackEntry is export {
  has $.handler;
  has @.if-cond;
  has @.unless-cond;
  has Bool $.prepend = False;
  has Str  $.kind    = 'normal';
  has Str  $.tag     = '';
}

role ModelCallbacks is export {

  my @EVENTS = <save create update destroy validation initialize find touch>;

  method !cb-pluralize(Str:D $event --> Str) {
    return $event ~ 'es' if $event ~~ /<[sxz]> $ | 'ch' $ | 'sh' $/;
    $event ~ 's';
  }

  method !cb-event-list(Str:D $event, Str:D $timing) {
    my $name = "$timing-" ~ self!cb-pluralize($event);
    self."$name"();
  }

  method !cb-cond-list($v) {
    return () unless $v.defined;
    given $v {
      when Positional { return $v.list }
      default         { return ($v,) }
    }
  }

  method !eval-cond(Mu:D $cond --> Bool) {
    given $cond {
      when Block { return so $cond(self) if $cond.arity > 0; return so $cond() }
      when Str   { return so self."$cond"() }
    }
    True;
  }

  method !cb-conditions-pass(CallbackEntry:D $entry --> Bool) {
    for $entry.if-cond -> $c {
      return False unless self!eval-cond($c);
    }
    for $entry.unless-cond -> $c {
      return False if self!eval-cond($c);
    }
    True;
  }

  method !cb-build-entry($handler, %opts, Str:D $kind = 'normal') {
    my @ifc      = self!cb-cond-list(%opts<if>);
    my @unlessc  = self!cb-cond-list(%opts<unless>);
    my Bool $prepend = so (%opts<prepend> // False);
    my Str  $tag = (%opts<tag> // ($handler ~~ Str ?? $handler !! '')).Str;
    CallbackEntry.new(:$handler, :if-cond(@ifc), :unless-cond(@unlessc), :$prepend, :$kind, :$tag);
  }

  method !cb-add(Str:D $event, Str:D $timing, @handlers, %opts, Str:D $kind = 'normal') {
    my @list := self!cb-event-list($event, $timing);
    for @handlers -> $h {
      my $entry = self!cb-build-entry($h, %opts, $kind);
      if $entry.prepend {
        @list.unshift: $entry;
      } else {
        @list.push: $entry;
      }
    }
    True;
  }

  method !cb-call-normal(CallbackEntry:D $entry) {
    my $h = $entry.handler;
    given $h {
      when Block {
        return $h.arity > 0 ?? $h(self) !! $h();
      }
      when Str {
        return self."$h"();
      }
    }
  }

  method !cb-terminator-for(Str:D $event, Str:D $timing) {
    my %terms := self.callback-terminators;
    my $key = "$timing-$event";
    return %terms{$key} if %terms{$key}:exists;
    %terms{'default'} // Nil;
  }

  method !cb-result-aborts(Str:D $event, Str:D $timing, $result --> Bool) {
    my $term = self!cb-terminator-for($event, $timing);
    if $term.defined && $term ~~ Block {
      return so $term($result);
    }
    so ($result === False);
  }

  method run-callback-chain(Str:D $event, Str:D $timing --> Bool) {
    my @entries := self!cb-event-list($event, $timing);
    for @entries -> $entry {
      next unless self!cb-conditions-pass($entry);
      my $result;
      my $aborted = False;
      {
        CATCH {
          when X::Callback::Abort {
            $aborted = True;
            return False;
          }
        }
        $result = self!cb-call-normal($entry);
      }
      return False if $aborted;
      return False if self!cb-result-aborts($event, $timing, $result);
    }
    True;
  }

  method run-around-chain(Str:D $event, &inner --> Bool) {
    my @entries := self!cb-event-list($event, 'around');
    my @active = @entries.grep({ self!cb-conditions-pass($_) });
    my Bool $proceed = True;
    my Bool $aborted = False;

    my &chain = -> { $proceed = inner() };
    for @active.reverse -> $entry {
      my &prev = &chain;
      my $h = $entry.handler;
      &chain = -> {
        CATCH {
          when X::Callback::Abort {
            $aborted = True;
            $proceed = False;
            return;
          }
        }
        my $yield-called = False;
        my &yield = -> { $yield-called = True; prev(); };
        given $h {
          when Block {
            if $h.arity >= 2 { $h(self, &yield) }
            elsif $h.arity == 1 { $h(&yield) }
            else { $h() }
          }
          when Str {
            self."$h"(&yield);
          }
        }
        # If user forgot to yield, treat as halt
        unless $yield-called {
          $proceed = False;
        }
      };
    }
    &chain();
    return False if $aborted;
    $proceed;
  }

  method skip-callback(:$event!, :$timing!, :$tag, :$handler) {
    my @list := self!cb-event-list($event, $timing);
    my @kept;
    for @list -> $e {
      my $remove = False;
      if $tag.defined && $e.tag eq $tag {
        $remove = True;
      }
      if $handler.defined && $e.handler === $handler {
        $remove = True;
      }
      @kept.push: $e unless $remove;
    }
    @list = @kept;
    True;
  }

  method set-callback(:$event!, :$timing!, :$handler!, *%opts) {
    my Str $kind = (%opts<kind> // 'normal').Str;
    self!cb-add($event, $timing, ($handler,), %opts, $kind);
  }

  method callbacks-for(:$event!, :$timing!) {
    self!cb-event-list($event, $timing).list;
  }

  method has-callback(:$event!, :$timing!, :$tag) {
    self!cb-event-list($event, $timing).first({ .tag eq $tag }).defined;
  }

  method callback-tags(:$event!, :$timing!) {
    self!cb-event-list($event, $timing).map(*.tag).grep(*.chars).list;
  }

  method set-callback-terminator(:$event, :$timing, Block:D :$block) {
    my %terms := self.callback-terminators;
    my $key = $event.defined ?? "{$timing // 'before'}-$event" !! 'default';
    %terms{$key} = $block;
    True;
  }

  multi method before-save(*@handlers, *%opts)    { self!cb-add('save',    'before', @handlers, %opts) }
  multi method before-create(*@handlers, *%opts)  { self!cb-add('create',  'before', @handlers, %opts) }
  multi method before-update(*@handlers, *%opts)  { self!cb-add('update',  'before', @handlers, %opts) }
  multi method before-destroy(*@handlers, *%opts) { self!cb-add('destroy', 'before', @handlers, %opts) }

  multi method after-save(*@handlers, *%opts)     { self!cb-add('save',    'after',  @handlers, %opts) }
  multi method after-create(*@handlers, *%opts)   { self!cb-add('create',  'after',  @handlers, %opts) }
  multi method after-update(*@handlers, *%opts)   { self!cb-add('update',  'after',  @handlers, %opts) }
  multi method after-destroy(*@handlers, *%opts)  { self!cb-add('destroy', 'after',  @handlers, %opts) }

  multi method around-save(*@handlers, *%opts)    { self!cb-add('save',    'around', @handlers, %opts, 'around') }
  multi method around-create(*@handlers, *%opts)  { self!cb-add('create',  'around', @handlers, %opts, 'around') }
  multi method around-update(*@handlers, *%opts)  { self!cb-add('update',  'around', @handlers, %opts, 'around') }
  multi method around-destroy(*@handlers, *%opts) { self!cb-add('destroy', 'around', @handlers, %opts, 'around') }

  multi method before-validation(*@handlers, *%opts) { self!cb-add('validation', 'before', @handlers, %opts) }
  multi method after-validation(*@handlers, *%opts)  { self!cb-add('validation', 'after',  @handlers, %opts) }

  multi method after-initialize(*@handlers, *%opts) { self!cb-add('initialize', 'after', @handlers, %opts) }
  multi method after-find(*@handlers, *%opts)       { self!cb-add('find',       'after', @handlers, %opts) }
  multi method after-touch(*@handlers, *%opts)      { self!cb-add('touch',      'after', @handlers, %opts) }

  method do-before-saves    (--> Bool) { self.run-callback-chain('save',    'before') }
  method do-before-creates  (--> Bool) { self.run-callback-chain('create',  'before') }
  method do-before-updates  (--> Bool) { self.run-callback-chain('update',  'before') }
  method do-before-destroys (--> Bool) { self.run-callback-chain('destroy', 'before') }

  method do-after-saves    { self.run-callback-chain('save',    'after') }
  method do-after-creates  { self.run-callback-chain('create',  'after') }
  method do-after-updates  { self.run-callback-chain('update',  'after') }
  method do-after-destroys { self.run-callback-chain('destroy', 'after') }

  method do-before-validations (--> Bool) { self.run-callback-chain('validation', 'before') }
  method do-after-validations          { self.run-callback-chain('validation', 'after') }
  method do-after-initializes          { self.run-callback-chain('initialize', 'after') }
  method do-after-finds                { self.run-callback-chain('find',       'after') }
  method do-after-touches              { self.run-callback-chain('touch',      'after') }

  method after-commit(*@handlers, *%opts)         { self!cb-add('commit',         'after', @handlers, %opts) }
  method after-rollback(*@handlers, *%opts)       { self!cb-add('rollback',       'after', @handlers, %opts) }
  method after-create-commit(*@handlers, *%opts)  { self!cb-add('create-commit',  'after', @handlers, %opts) }
  method after-update-commit(*@handlers, *%opts)  { self!cb-add('update-commit',  'after', @handlers, %opts) }
  method after-destroy-commit(*@handlers, *%opts) { self!cb-add('destroy-commit', 'after', @handlers, %opts) }
  method after-save-commit(*@handlers, *%opts)    { self!cb-add('save-commit',    'after', @handlers, %opts) }

  method !run-txn-list(Str:D $event) {
    my @entries := self!cb-event-list($event, 'after');
    for @entries -> $entry {
      next unless self!cb-conditions-pass($entry);
      {
        CATCH {
          when X::Callback::Abort { return }
        }
        self!cb-call-normal($entry);
      }
    }
  }

  method run-after-commit(:%kinds) {
    if %kinds<create> {
      self!run-txn-list('create-commit');
    } elsif %kinds<update> {
      self!run-txn-list('update-commit');
    }
    if %kinds<destroy> {
      self!run-txn-list('destroy-commit');
    }
    if %kinds<create> || %kinds<update> {
      self!run-txn-list('save-commit');
    }
    self!run-txn-list('commit');
  }

  method run-after-rollback(:%kinds) {
    self!run-txn-list('rollback');
  }
}
