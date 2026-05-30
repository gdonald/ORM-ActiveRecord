use ORM::ActiveRecord::Model;

unit module Validation::Associated;

class Phbook is Model is export {
  submethod BUILD {
    self.belongs-to: phlibrary => %(class-name => 'Phlibrary', optional => True);
    self.validate: 'title', { :presence }
  }
}

class Phlibrary is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks';
  }
}

class Phlibrary2 is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook', foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates: <phbooks>, { :associated, message => 'has bad children' }
  }
}

class PhlibIf is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook', foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :if => { self.name eq 'Guarded' } };
  }
}

class PhlibUnless is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook', foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :unless => { self.name eq 'Skip' } };
  }
}

class PhlibOn is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook', foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { on => { :audit } };
  }
}

class PhlibStrict is Model is export {
  method table-name { 'phlibraries' }

  submethod BUILD {
    self.has-many: phbooks => %(class-name => 'Phbook', foreign-key => 'phlibrary_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'phbooks', { :strict };
  }
}

GLOBAL::<Phbook>       := Phbook;
GLOBAL::<Phlibrary>    := Phlibrary;
GLOBAL::<Phlibrary2>   := Phlibrary2;
GLOBAL::<PhlibIf>      := PhlibIf;
GLOBAL::<PhlibUnless>  := PhlibUnless;
GLOBAL::<PhlibOn>      := PhlibOn;
GLOBAL::<PhlibStrict>  := PhlibStrict;
