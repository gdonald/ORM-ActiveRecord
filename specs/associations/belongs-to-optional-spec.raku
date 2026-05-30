use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Page;
use Models::Passport;
use Models::Article;
use Models::Attachment;
use Models::Picture;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'belongs-to optional / required', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'default required', {
    it 'is invalid without parent', {
      my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
      expect($orphan.is-invalid).to.be-truthy;
    }

    it 'records error against the FK field', {
      my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.is-invalid;
      expect($orphan.errors.errors.first.field.name).to.eq('user_id');
    }

    it 'error message indicates parent must exist', {
      my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.is-invalid;
      expect($orphan.errors.errors.first.message).to.match(/'exist'/);
    }

    it 'save returns False without parent', {
      my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
      expect($orphan.save).to.be-falsy;
    }

    it 'id remains 0 when save fails', {
      my $orphan = Page.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.save;
      expect($orphan.id).to.eq(0);
    }

    it 'is valid with parent', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $page = Page.create({user => $alice, name => 'About'});
      expect($page.is-valid).to.be-truthy;
    }

    it 'persists with parent', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $page = Page.create({user => $alice, name => 'About'});
      expect($page.id).to.be-greater-than(0);
    }

    it 'is valid with FK set directly', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $page2 = Page.new(:id(0), :record({attrs => {name => 'Direct', user_id => $alice.id}}));
      expect($page2.is-valid).to.be-truthy;
    }

    it 'saves with FK set directly', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $page2 = Page.new(:id(0), :record({attrs => {name => 'Direct', user_id => $alice.id}}));
      $page2.save;
      expect($page2.id).to.be-greater-than(0);
    }
  }

  context 'optional: True', {
    it 'is valid without parent', {
      my $passport = Passport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      expect($passport.is-valid).to.be-truthy;
    }

    it 'save succeeds without parent', {
      my $passport = Passport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      expect($passport.save).to.be-truthy;
    }

    it 'persists without parent', {
      my $passport = Passport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      $passport.save;
      expect($passport.id).to.be-greater-than(0);
    }
  }

  context 'required: False (alias)', {
    it 'is valid without parent', {
      my $orphan-article = Article.new(:id(0), :record({attrs => {title => 'No Author', body => '...'}}));
      expect($orphan-article.is-valid).to.be-truthy;
    }

    it 'saves without parent', {
      my $orphan-article = Article.new(:id(0), :record({attrs => {title => 'No Author', body => '...'}}));
      expect($orphan-article.save).to.be-truthy;
    }
  }

  context 'polymorphic + optional', {
    it 'saves without target', {
      my $bare-attach = Attachment.create({name => 'unattached.txt'});
      expect($bare-attach.id).to.be-greater-than(0);
    }

    it 'saves with target', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $a-with = Attachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.id).to.be-greater-than(0);
    }

    it 'fills attachable_id', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $a-with = Attachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.attrs<attachable_id>).to.eq($alice.id);
    }

    it 'fills attachable_type', {
      my $alice = User.create({fname => 'Alice', lname => 'A'});
      my $a-with = Attachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.attrs<attachable_type>).to.eq('User');
    }
  }

  context 'polymorphic + default-required', {
    it 'is invalid without target', {
      my $bare-pic = Picture.new(:id(0), :record({attrs => {name => 'orphan.png'}}));
      expect($bare-pic.is-invalid).to.be-truthy;
    }

    it 'is invalid when only _id is set', {
      my $half = Picture.new(:id(0), :record({attrs => {name => 'half.png', imageable_id => 1}}));
      expect($half.is-invalid).to.be-truthy;
    }
  }

  context 'is-belongs-to-optional predicate', {
    it 'returns False on missing key', {
      expect(User.new(:id(0)).is-belongs-to-optional('user')).to.be-falsy;
    }

    it 'returns True for optional: True', {
      expect(Passport.new(:id(0)).is-belongs-to-optional('owner')).to.be-truthy;
    }

    it 'returns False when default-required', {
      expect(Page.new(:id(0)).is-belongs-to-optional('user')).to.be-falsy;
    }
  }
}
