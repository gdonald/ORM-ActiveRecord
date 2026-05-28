use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class Phlibrary  {...}
class Phlibrary2 {...}

class Phbook is Model {
  submethod BUILD {
    self.belongs-to: phlibrary => %(class => Phlibrary, optional => True);
    self.validate: 'title', { :presence }
  }
}

class Phlibrary is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook);
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks';
  }
}

class Phlibrary2 is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook, foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates: <phbooks>, { :associated, message => 'has bad children' }
  }
}

class PhlibIf is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook, foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :if => { self.name eq 'Guarded' } };
  }
}

class PhlibUnless is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook, foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :unless => { self.name eq 'Skip' } };
  }
}

class PhlibOn is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook, foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { on => { :audit } };
  }
}

class PhlibStrict is Model {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class => Phbook, foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :strict };
  }
}

sub clean {
  DB.shared.delete-records(:table('phbooks'),     :where({}));
  DB.shared.delete-records(:table('phlibraries'), :where({}));
}

sub seed-bad-child($class, Str:D $name) {
  my $lib = $class.create({name => $name});
  Phbook.new(:id(0), :record({attrs => {title => '', phlibrary_id => $lib.id}})).save(:!validate);
  $class.find($lib.id);
}

describe 'validates-associated', {
  before-each { clean }
  after-each  { clean }

  context 'a library with no books', {
    it 'is valid', {
      my $lib = Phlibrary.create({name => 'Main'});
      expect($lib.is-valid).to.be-truthy;
    }

    it 'is saved with an id', {
      my $lib = Phlibrary.create({name => 'Main'});
      expect($lib.id).to.be-greater-than(0);
    }
  }

  context 'a library with all-valid books', {
    it 'is valid', {
      my $lib = Phlibrary.create({name => 'Main'});
      Phbook.create({title => 'Good Book', phlibrary_id => $lib.id});
      my $loaded = Phlibrary.find($lib.id);
      expect($loaded.is-valid).to.be-truthy;
    }
  }

  context 'a library with an invalid child book', {
    before-each {
      my $lib = Phlibrary.create({name => 'Main'});
      Phbook.new(:id(0), :record({attrs => {title => '', phlibrary_id => $lib.id}})).save(:!validate);
    }

    it 'is invalid', {
      my $lib = Phlibrary.first;
      expect($lib.is-valid).to.be-falsy;
    }

    it 'records "is invalid" on phbooks', {
      my $lib = Phlibrary.first;
      $lib.is-valid;
      expect($lib.errors.phbooks[0]).to.eq('is invalid');
    }

    it 'supports a custom message via the validates DSL', {
      my $orig = Phlibrary.first;
      my $lib2 = Phlibrary2.find($orig.id);
      expect($lib2.is-valid).to.be-falsy;
    }

    it 'uses the custom message text', {
      my $orig = Phlibrary.first;
      my $lib2 = Phlibrary2.find($orig.id);
      $lib2.is-valid;
      expect($lib2.errors.phbooks[0]).to.eq('has bad children');
    }
  }
}

describe 'validates-associated options', {
  before-each { clean }
  after-each  { clean }

  context ':if guard', {
    it 'rolls up the child when :if is true', {
      expect(seed-bad-child(PhlibIf, 'Guarded').is-invalid).to.be-truthy;
    }

    it 'skips the child when :if is false', {
      expect(seed-bad-child(PhlibIf, 'Open').is-valid).to.be-truthy;
    }
  }

  context ':unless guard', {
    it 'skips the child when :unless is true', {
      expect(seed-bad-child(PhlibUnless, 'Skip').is-valid).to.be-truthy;
    }

    it 'rolls up the child when :unless is false', {
      expect(seed-bad-child(PhlibUnless, 'Run').is-invalid).to.be-truthy;
    }
  }

  context 'on: context', {
    it 'rolls up the child under the named context', {
      expect(seed-bad-child(PhlibOn, 'Main').is-invalid(:context<audit>)).to.be-truthy;
    }

    it 'skips the child in the default context', {
      expect(seed-bad-child(PhlibOn, 'Main').is-valid).to.be-truthy;
    }
  }

  context 'strict', {
    it 'raises X::StrictValidationFailed for an invalid child', {
      my $lib = seed-bad-child(PhlibStrict, 'Main');
      my $caught;
      try { $lib.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'does not raise when every child is valid', {
      my $lib = PhlibStrict.create({name => 'Clean'});
      expect(PhlibStrict.find($lib.id).is-valid).to.be-truthy;
    }
  }
}
