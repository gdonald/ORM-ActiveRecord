use ORM::ActiveRecord::Errors::X;

role SqlAdvisoryLocks is export {
  has Bool $.advisory-locks is rw = True;

  # Engines that have no advisory-lock primitive (SQLite) override this to
  # False; with-advisory-lock then runs the block without locking.
  method supports-advisory-locks(--> Bool) { False }

  method !advisory-lock-active(--> Bool) {
    $!advisory-locks && self.supports-advisory-locks;
  }

  method with-advisory-lock(Str:D $name, &block, :$timeout) {
    return block() unless self!advisory-lock-active;

    die X::AdvisoryLock.new(:$name) unless self.get-advisory-lock($name, :$timeout);

    # The release must run only after a successful acquire, so it lives in its
    # own block. A LEAVE fires on every exit of its enclosing block, including
    # the early return and die above, so placing it there would release a lock
    # that was never taken.
    return do {
      LEAVE self.release-advisory-lock($name);
      block();
    }
  }

  # Engines override these. The defaults make a no-support adapter report that
  # it never holds a lock rather than throwing.
  method get-advisory-lock(Str:D $name, :$timeout --> Bool)  { False }
  method release-advisory-lock(Str:D $name --> Bool)         { False }
}
