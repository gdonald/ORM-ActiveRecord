use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use Validation::Associated;

%*ENV<DISABLE-SQL-LOG> = True;

sub clean {
  DB.shared.delete-records(:table('manuals'),     :where({}));
  DB.shared.delete-records(:table('archives'), :where({}));
}

sub seed-bad-child($class, Str:D $name) {
  my $lib = $class.create({name => $name});
  Manual.new(:id(0), :record({attrs => {title => '', archive_id => $lib.id}})).save(:!validate);
  $class.find($lib.id);
}

describe 'validates-associated', {
  before-each { clean }
  after-each  { clean }

  context 'a library with no books', {
    it 'is valid', {
      my $lib = Archive.create({name => 'Main'});
      expect($lib.is-valid).to.be-truthy;
    }

    it 'is saved with an id', {
      my $lib = Archive.create({name => 'Main'});
      expect($lib.id).to.be-greater-than(0);
    }
  }

  context 'a library with all-valid books', {
    it 'is valid', {
      my $lib = Archive.create({name => 'Main'});
      Manual.create({title => 'Good Book', archive_id => $lib.id});
      my $loaded = Archive.find($lib.id);
      expect($loaded.is-valid).to.be-truthy;
    }
  }

  context 'a library with an invalid child book', {
    before-each {
      my $lib = Archive.create({name => 'Main'});
      Manual.new(:id(0), :record({attrs => {title => '', archive_id => $lib.id}})).save(:!validate);
    }

    it 'is invalid', {
      my $lib = Archive.first;
      expect($lib.is-valid).to.be-falsy;
    }

    it 'records "is invalid" on manuals', {
      my $lib = Archive.first;
      $lib.is-valid;
      expect($lib.errors.manuals[0]).to.eq('is invalid');
    }

    it 'supports a custom message via the validates DSL', {
      my $orig = Archive.first;
      my $lib2 = Repository.find($orig.id);
      expect($lib2.is-valid).to.be-falsy;
    }

    it 'uses the custom message text', {
      my $orig = Archive.first;
      my $lib2 = Repository.find($orig.id);
      $lib2.is-valid;
      expect($lib2.errors.manuals[0]).to.eq('has bad children');
    }
  }
}

describe 'validates-associated options', {
  before-each { clean }
  after-each  { clean }

  context ':if guard', {
    it 'rolls up the child when :if is true', {
      expect(seed-bad-child(Vault, 'Guarded').is-invalid).to.be-truthy;
    }

    it 'skips the child when :if is false', {
      expect(seed-bad-child(Vault, 'Open').is-valid).to.be-truthy;
    }
  }

  context ':unless guard', {
    it 'skips the child when :unless is true', {
      expect(seed-bad-child(Depot, 'Skip').is-valid).to.be-truthy;
    }

    it 'rolls up the child when :unless is false', {
      expect(seed-bad-child(Depot, 'Run').is-invalid).to.be-truthy;
    }
  }

  context 'on: context', {
    it 'rolls up the child under the named context', {
      expect(seed-bad-child(Registry, 'Main').is-invalid(:context<audit>)).to.be-truthy;
    }

    it 'skips the child in the default context', {
      expect(seed-bad-child(Registry, 'Main').is-valid).to.be-truthy;
    }
  }

  context 'strict', {
    it 'raises X::StrictValidationFailed for an invalid child', {
      my $lib = seed-bad-child(Catalog, 'Main');
      my $caught;
      try { $lib.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'does not raise when every child is valid', {
      my $lib = Catalog.create({name => 'Clean'});
      expect(Catalog.find($lib.id).is-valid).to.be-truthy;
    }
  }
}
