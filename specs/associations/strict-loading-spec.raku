use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class Slthing { ... }

class Slowner is Model {
  submethod BUILD {
    self.has-many: slthings => %(class => Slthing, strict-loading => True);
  }
}

class Slthing is Model {
  submethod BUILD {
    self.belongs-to: slowner => %(class => Slthing, strict-loading => True, optional => True);
  }
}

class Slowner2 is Model {
  method table-name { 'slowners' }

  submethod BUILD {
    self.has-many: slthings => %(class => Slthing, foreign-key => 'slowner_id');
  }
}

class Slowner3 is Model {
  method table-name { 'slowners' }

  submethod BUILD {
    self.strict-loading-by-default;
    self.has-many: slthings => %(class => Slthing, foreign-key => 'slowner_id');
  }
}

sub sl-clean {
  clean-shared-tables;
}

describe 'strict-loading', {
  before-each { sl-clean }
  after-each  { sl-clean }

  context 'per-relation strict-loading', {
    it 'raises on access', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      expect({ $owner.slthings }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $err;
      try { $owner.slthings; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }

    it 'message mentions strict-loading', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $err;
      try { $owner.slthings; CATCH { default { $err = $_ } } }
      expect($err.message).to.match(/'strict-loading'/);
    }

    it 'error names the association', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $err;
      try { $owner.slthings; CATCH { default { $err = $_ } } }
      expect($err.association).to.eq('slthings');
    }

    it 'error names the model', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $err;
      try { $owner.slthings; CATCH { default { $err = $_ } } }
      expect($err.model).to.match(/'Slowner'/);
    }

    it 'raises on belongs-to access', {
      my $owner = Slowner.create({name => 'strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $child = Slthing.find-by({label => 'x'});
      expect({ $child.slowner }).to.raise-error;
    }
  }

  context 'per-instance make-strict-loading', {
    it 'is-strict-loading defaults to False', {
      my $owner = Slowner.create({name => 'strict-2'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner2 = Slowner2.find($owner.id);
      expect($owner2.is-strict-loading).to.be-falsy;
    }

    it 'lazy loads by default', {
      my $owner = Slowner.create({name => 'strict-2'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner2 = Slowner2.find($owner.id);
      expect({ $owner2.slthings }).not.to.raise-error;
    }

    it 'flag visible after make-strict-loading', {
      my $owner = Slowner.create({name => 'strict-3'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner2b = Slowner2.find($owner.id);
      $owner2b.make-strict-loading;
      expect($owner2b.is-strict-loading).to.be-truthy;
    }

    it 'raises on lazy access after make-strict-loading', {
      my $owner = Slowner.create({name => 'strict-4'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner2b = Slowner2.find($owner.id);
      $owner2b.make-strict-loading;
      expect({ $owner2b.slthings }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError per-instance', {
      my $owner = Slowner.create({name => 'strict-5'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner2b = Slowner2.find($owner.id);
      $owner2b.make-strict-loading;
      my $err;
      try { $owner2b.slthings; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }
  }

  context 'class-level strict-loading-by-default', {
    it 'is visible via predicate', {
      my $owner = Slowner.create({name => 'class-strict'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner3 = Slowner3.find($owner.id);
      expect($owner3.is-strict-loading-by-default).to.be-truthy;
    }

    it 'raises on lazy access', {
      my $owner = Slowner.create({name => 'class-strict-2'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner3 = Slowner3.find($owner.id);
      expect({ $owner3.slthings }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError class-level', {
      my $owner = Slowner.create({name => 'class-strict-3'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my $owner3 = Slowner3.find($owner.id);
      my $err;
      try { $owner3.slthings; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }
  }

  context 'preload bypass', {
    it 'per-relation strict-loading allows preloaded access', {
      my $owner = Slowner.create({name => 'preload-bypass'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my @preloaded = Slowner.where({}).preload(:slthings).all;
      expect({ @preloaded.first.slthings }).not.to.raise-error;
    }

    it 'preload populates the assoc-cache', {
      my $owner = Slowner.create({name => 'preload-bypass-2'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my @preloaded = Slowner.where({}).preload(:slthings).all;
      expect(@preloaded.first.assoc-cache<slthings>:exists).to.be-truthy;
    }

    it 'class-level strict-loading-by-default allows preloaded access', {
      my $owner = Slowner.create({name => 'preload-bypass-3'});
      Slthing.create({label => 'x', slowner_id => $owner.id});
      my @preloaded3 = Slowner3.where({}).preload(:slthings).all;
      expect({ @preloaded3.first.slthings }).not.to.raise-error;
    }
  }
}
