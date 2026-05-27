use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

class Aschild { ... }

class Asparent is Model {
  submethod BUILD {
    self.validate: 'name', { :presence };
    self.has-many: aschilds => %(class => Aschild);
  }
}

class Aschild is Model {
  submethod BUILD {
    self.belongs-to: asparent => %(
      class      => Asparent,
      autosave   => True,
      validate   => True,
      optional   => True,
    );
  }
}

sub as-clean {
  clean-shared-tables;
}

describe 'autosave + validate on belongs-to', {
  before-each { as-clean }
  after-each  { as-clean }

  context 'autosave: True saves a new parent before the child', {
    it 'parent starts unsaved', {
      my $new-parent = Asparent.new(:id(0), :record({attrs => {name => 'Parent'}}));
      expect($new-parent.id).to.eq(0);
    }

    it 'saves the parent', {
      my $new-parent = Asparent.new(:id(0), :record({attrs => {name => 'Parent'}}));
      Aschild.create({title => 'C', asparent => $new-parent});
      expect($new-parent.id).to.be-greater-than(0);
    }

    it 'fills FK column on child', {
      my $new-parent = Asparent.new(:id(0), :record({attrs => {name => 'Parent'}}));
      my $child = Aschild.create({title => 'C', asparent => $new-parent});
      expect($child.attrs<asparent_id>).to.eq($new-parent.id);
    }
  }

  it 'autosave on an existing parent persists changes', {
    my $new-parent = Asparent.new(:id(0), :record({attrs => {name => 'Parent'}}));
    Aschild.create({title => 'C', asparent => $new-parent});
    my $loaded = Asparent.find($new-parent.id);
    $loaded.attrs<name> = 'Parent-Renamed';
    Aschild.create({title => 'C2', asparent => $loaded});
    my $reloaded = Asparent.find($new-parent.id);

    expect($reloaded.attrs<name>).to.eq('Parent-Renamed');
  }

  context 'cascade validation with invalid parent', {
    it 'parent fails its own presence validation', {
      my $invalid-parent = Asparent.new(:id(0), :record({attrs => {name => ''}}));
      expect($invalid-parent.is-valid).to.be-falsy;
    }

    it 'child with validate: True fails when parent invalid', {
      my $invalid-parent = Asparent.new(:id(0), :record({attrs => {name => ''}}));
      my $cv-child = Aschild.new(:id(0), :record({attrs => {title => 'X', asparent => $invalid-parent}}));
      expect($cv-child.is-valid).to.be-falsy;
    }

    it 'child accumulates an error from the parent', {
      my $invalid-parent = Asparent.new(:id(0), :record({attrs => {name => ''}}));
      my $cv-child = Aschild.new(:id(0), :record({attrs => {title => 'X', asparent => $invalid-parent}}));
      $cv-child.is-valid;
      expect($cv-child.errors.errors.elems).to.be-greater-than(0);
    }

    it 'cascaded error reads "is invalid"', {
      my $invalid-parent = Asparent.new(:id(0), :record({attrs => {name => ''}}));
      my $cv-child = Aschild.new(:id(0), :record({attrs => {title => 'X', asparent => $invalid-parent}}));
      $cv-child.is-valid;
      expect($cv-child.errors.errors.first.message).to.match(/'is invalid'/);
    }
  }

  context 'valid parent passes through', {
    it 'child is valid', {
      my $good-parent = Asparent.create({name => 'OK'});
      my $good-child = Aschild.new(:id(0), :record({attrs => {title => 'Y', asparent => $good-parent}}));
      expect($good-child.is-valid).to.be-truthy;
    }

    it 'child saves', {
      my $good-parent = Asparent.create({name => 'OK'});
      my $good-child = Aschild.new(:id(0), :record({attrs => {title => 'Y', asparent => $good-parent}}));
      expect($good-child.save).to.be-truthy;
    }
  }
}
