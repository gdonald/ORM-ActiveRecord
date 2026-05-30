use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::User;
use Models::Page;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'autosave + validate on belongs-to', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'autosave: True saves a new parent before the child', {
    it 'parent starts unsaved', {
      my $new-parent = User.new(:id(0), :record({attrs => {fname => 'Parent'}}));
      expect($new-parent.id).to.eq(0);
    }

    it 'saves the parent', {
      my $new-parent = User.new(:id(0), :record({attrs => {fname => 'Parent'}}));
      Page.create({name => 'C', autosave-user => $new-parent});
      expect($new-parent.id).to.be-greater-than(0);
    }

    it 'fills FK column on child', {
      my $new-parent = User.new(:id(0), :record({attrs => {fname => 'Parent'}}));
      my $child = Page.create({name => 'C', autosave-user => $new-parent});
      expect($child.attrs<user_id>).to.eq($new-parent.id);
    }
  }

  it 'autosave on an existing parent persists changes', {
    my $new-parent = User.new(:id(0), :record({attrs => {fname => 'Parent'}}));
    Page.create({name => 'C', autosave-user => $new-parent});
    my $loaded = User.find($new-parent.id);
    $loaded.attrs<fname> = 'Renamed';
    Page.create({name => 'C2', autosave-user => $loaded});
    my $reloaded = User.find($new-parent.id);

    expect($reloaded.attrs<fname>).to.eq('Renamed');
  }

  context 'cascade validation with invalid parent', {
    it 'parent fails its own presence validation', {
      my $invalid-parent = User.new(:id(0), :record({attrs => {fname => ''}}));
      expect($invalid-parent.is-valid).to.be-falsy;
    }

    it 'child with validate: True fails when parent invalid', {
      my $invalid-parent = User.new(:id(0), :record({attrs => {fname => ''}}));
      my $cv-child = Page.new(:id(0), :record({attrs => {name => 'X', autosave-user => $invalid-parent}}));
      expect($cv-child.is-valid).to.be-falsy;
    }

    it 'child accumulates an error from the parent', {
      my $invalid-parent = User.new(:id(0), :record({attrs => {fname => ''}}));
      my $cv-child = Page.new(:id(0), :record({attrs => {name => 'X', autosave-user => $invalid-parent}}));
      $cv-child.is-valid;
      expect($cv-child.errors.errors.elems).to.be-greater-than(0);
    }

    it 'cascaded error reads "is invalid"', {
      my $invalid-parent = User.new(:id(0), :record({attrs => {fname => ''}}));
      my $cv-child = Page.new(:id(0), :record({attrs => {name => 'X', autosave-user => $invalid-parent}}));
      $cv-child.is-valid;
      expect($cv-child.errors.errors.first.message).to.match(/'is invalid'/);
    }
  }

  context 'valid parent passes through', {
    it 'child is valid', {
      my $good-parent = User.create({fname => 'OK'});
      my $good-child = Page.new(:id(0), :record({attrs => {name => 'Y', autosave-user => $good-parent}}));
      expect($good-child.is-valid).to.be-truthy;
    }

    it 'child saves', {
      my $good-parent = User.create({fname => 'OK'});
      my $good-child = Page.new(:id(0), :record({attrs => {name => 'Y', autosave-user => $good-parent}}));
      expect($good-child.save).to.be-truthy;
    }
  }
}
