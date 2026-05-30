use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use Models::Track;

%*ENV<DISABLE-SQL-LOG> = True;

class Studio is Model {
  submethod BUILD {
    self.has-many: tracks => %(class => Track, strict-loading => True);
  }
}

class Garage is Model {
  method table-name { 'studios' }

  submethod BUILD {
    self.has-many: tracks => %(class => Track, foreign-key => 'studio_id');
  }
}

class Atelier is Model {
  method table-name { 'studios' }

  submethod BUILD {
    self.strict-loading-by-default;
    self.has-many: tracks => %(class => Track, foreign-key => 'studio_id');
  }
}

describe 'strict-loading', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'per-relation strict-loading', {
    it 'raises on access', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      expect({ $owner.tracks }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $err;
      try { $owner.tracks; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }

    it 'message mentions strict-loading', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $err;
      try { $owner.tracks; CATCH { default { $err = $_ } } }
      expect($err.message).to.match(/'strict-loading'/);
    }

    it 'error names the association', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $err;
      try { $owner.tracks; CATCH { default { $err = $_ } } }
      expect($err.association).to.eq('tracks');
    }

    it 'error names the model', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $err;
      try { $owner.tracks; CATCH { default { $err = $_ } } }
      expect($err.model).to.match(/'Studio'/);
    }

    it 'raises on belongs-to access', {
      my $owner = Studio.create({name => 'strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $child = Track.find-by({label => 'x'});
      expect({ $child.studio }).to.raise-error;
    }
  }

  context 'per-instance make-strict-loading', {
    it 'is-strict-loading defaults to False', {
      my $owner = Studio.create({name => 'strict-2'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner2 = Garage.find($owner.id);
      expect($owner2.is-strict-loading).to.be-falsy;
    }

    it 'lazy loads by default', {
      my $owner = Studio.create({name => 'strict-2'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner2 = Garage.find($owner.id);
      expect({ $owner2.tracks }).not.to.raise-error;
    }

    it 'flag visible after make-strict-loading', {
      my $owner = Studio.create({name => 'strict-3'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner2b = Garage.find($owner.id);
      $owner2b.make-strict-loading;
      expect($owner2b.is-strict-loading).to.be-truthy;
    }

    it 'raises on lazy access after make-strict-loading', {
      my $owner = Studio.create({name => 'strict-4'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner2b = Garage.find($owner.id);
      $owner2b.make-strict-loading;
      expect({ $owner2b.tracks }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError per-instance', {
      my $owner = Studio.create({name => 'strict-5'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner2b = Garage.find($owner.id);
      $owner2b.make-strict-loading;
      my $err;
      try { $owner2b.tracks; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }
  }

  context 'class-level strict-loading-by-default', {
    it 'is visible via predicate', {
      my $owner = Studio.create({name => 'class-strict'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner3 = Atelier.find($owner.id);
      expect($owner3.is-strict-loading-by-default).to.be-truthy;
    }

    it 'raises on lazy access', {
      my $owner = Studio.create({name => 'class-strict-2'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner3 = Atelier.find($owner.id);
      expect({ $owner3.tracks }).to.raise-error;
    }

    it 'raises X::StrictLoadingViolationError class-level', {
      my $owner = Studio.create({name => 'class-strict-3'});
      Track.create({label => 'x', studio_id => $owner.id});
      my $owner3 = Atelier.find($owner.id);
      my $err;
      try { $owner3.tracks; CATCH { default { $err = $_ } } }
      expect($err.WHAT.^name).to.eq('X::StrictLoadingViolationError');
    }
  }

  context 'preload bypass', {
    it 'per-relation strict-loading allows preloaded access', {
      my $owner = Studio.create({name => 'preload-bypass'});
      Track.create({label => 'x', studio_id => $owner.id});
      my @preloaded = Studio.where({}).preload(:tracks).all;
      expect({ @preloaded.first.tracks }).not.to.raise-error;
    }

    it 'preload populates the assoc-cache', {
      my $owner = Studio.create({name => 'preload-bypass-2'});
      Track.create({label => 'x', studio_id => $owner.id});
      my @preloaded = Studio.where({}).preload(:tracks).all;
      expect(@preloaded.first.assoc-cache<tracks>:exists).to.be-truthy;
    }

    it 'class-level strict-loading-by-default allows preloaded access', {
      my $owner = Studio.create({name => 'preload-bypass-3'});
      Track.create({label => 'x', studio_id => $owner.id});
      my @preloaded3 = Atelier.where({}).preload(:tracks).all;
      expect({ @preloaded3.first.tracks }).not.to.raise-error;
    }
  }
}
