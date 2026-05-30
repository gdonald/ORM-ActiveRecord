use ORM::ActiveRecord::Model;

unit module Validation::Associated;

class Manual is Model is export {
  submethod BUILD {
    self.belongs-to: archive => %(class-name => 'Archive', optional => True);
    self.validate: 'title', { :presence }
  }
}

class Archive is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual');
    self.validate: 'name', { :presence }
    self.validates-associated: 'manuals';
  }
}

class Repository is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual', foreign-key => 'archive_id');
    self.validate: 'name', { :presence }
    self.validates: <manuals>, { :associated, message => 'has bad children' }
  }
}

class Vault is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual', foreign-key => 'archive_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'manuals', { :if => { self.name eq 'Guarded' } };
  }
}

class Depot is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual', foreign-key => 'archive_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'manuals', { :unless => { self.name eq 'Skip' } };
  }
}

class Registry is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual', foreign-key => 'archive_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'manuals', { on => { :audit } };
  }
}

class Catalog is Model is export {
  method table-name { 'archives' }

  submethod BUILD {
    self.has-many: manuals => %(class-name => 'Manual', foreign-key => 'archive_id');
    self.validate: 'name', { :presence }
    self.validates-associated: 'manuals', { :strict };
  }
}

GLOBAL::<Manual>     := Manual;
GLOBAL::<Archive>    := Archive;
GLOBAL::<Repository> := Repository;
GLOBAL::<Vault>      := Vault;
GLOBAL::<Depot>      := Depot;
GLOBAL::<Registry>   := Registry;
GLOBAL::<Catalog>    := Catalog;
