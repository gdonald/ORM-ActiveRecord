use ORM::ActiveRecord::Model;

unit module Validation::GuardSkip;

# A validation whose `if` guard is false must not run at all. Acceptance and
# confirmation are the two that ran anyway: acceptance tested the guard with
# `unless`, and confirmation's `&&` bound tighter than its `||`, leaving the
# second branch unguarded.
class GuardedContract is Model is export {
  method table-name { 'contracts' }

  submethod BUILD {
    self.validate: 'terms', { :acceptance, :if => { self.guard-open } }
  }

  method guard-open { False }
}

class GuardedClient is Model is export {
  method table-name { 'clients' }

  submethod BUILD {
    self.validate: 'email', { :confirmation, :if => { self.guard-open } }
  }

  method guard-open { False }
}

class OpenGuardContract is Model is export {
  method table-name { 'contracts' }

  submethod BUILD {
    self.validate: 'terms', { :acceptance, :if => { self.guard-open } }
  }

  method guard-open { True }
}

GLOBAL::<GuardedContract>   := GuardedContract;
GLOBAL::<GuardedClient>     := GuardedClient;
GLOBAL::<OpenGuardContract> := OpenGuardContract;
