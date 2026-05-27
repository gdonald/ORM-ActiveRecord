use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class BoUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }
}

class BoPage is Model {
  method table-name { 'pages' }

  submethod BUILD {
    self.belongs-to: user => %(class => BoUser, foreign-key => 'user_id');
  }
}

class BoPassport is Model {
  method table-name { 'passports' }

  submethod BUILD {
    self.belongs-to: owner => %(class => BoUser, foreign-key => 'owner_id', optional => True);
  }
}

class BoArticle is Model {
  method table-name { 'articles' }

  submethod BUILD {
    self.belongs-to: author => %(class => BoUser, foreign-key => 'author_id', required => False);
  }
}

class BoAttachment is Model {
  method table-name { 'attachments' }

  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
  }
}

class BoPicture is Model {
  method table-name { 'pictures' }

  submethod BUILD {
    self.belongs-to: imageable => :polymorphic;
  }
}

describe 'belongs-to optional / required', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'default required', {
    it 'is invalid without parent', {
      my $orphan = BoPage.new(:id(0), :record({attrs => {name => 'Home'}}));
      expect($orphan.is-invalid).to.be-truthy;
    }

    it 'records error against the FK field', {
      my $orphan = BoPage.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.is-invalid;
      expect($orphan.errors.errors.first.field.name).to.eq('user_id');
    }

    it 'error message indicates parent must exist', {
      my $orphan = BoPage.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.is-invalid;
      expect($orphan.errors.errors.first.message).to.match(/'exist'/);
    }

    it 'save returns False without parent', {
      my $orphan = BoPage.new(:id(0), :record({attrs => {name => 'Home'}}));
      expect($orphan.save).to.be-falsy;
    }

    it 'id remains 0 when save fails', {
      my $orphan = BoPage.new(:id(0), :record({attrs => {name => 'Home'}}));
      $orphan.save;
      expect($orphan.id).to.eq(0);
    }

    it 'is valid with parent', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $page = BoPage.create({user => $alice, name => 'About'});
      expect($page.is-valid).to.be-truthy;
    }

    it 'persists with parent', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $page = BoPage.create({user => $alice, name => 'About'});
      expect($page.id).to.be-greater-than(0);
    }

    it 'is valid with FK set directly', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $page2 = BoPage.new(:id(0), :record({attrs => {name => 'Direct', user_id => $alice.id}}));
      expect($page2.is-valid).to.be-truthy;
    }

    it 'saves with FK set directly', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $page2 = BoPage.new(:id(0), :record({attrs => {name => 'Direct', user_id => $alice.id}}));
      $page2.save;
      expect($page2.id).to.be-greater-than(0);
    }
  }

  context 'optional: True', {
    it 'is valid without parent', {
      my $passport = BoPassport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      expect($passport.is-valid).to.be-truthy;
    }

    it 'save succeeds without parent', {
      my $passport = BoPassport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      expect($passport.save).to.be-truthy;
    }

    it 'persists without parent', {
      my $passport = BoPassport.new(:id(0), :record({attrs => {number => 'AB123'}}));
      $passport.save;
      expect($passport.id).to.be-greater-than(0);
    }
  }

  context 'required: False (alias)', {
    it 'is valid without parent', {
      my $orphan-article = BoArticle.new(:id(0), :record({attrs => {title => 'No Author', body => '...'}}));
      expect($orphan-article.is-valid).to.be-truthy;
    }

    it 'saves without parent', {
      my $orphan-article = BoArticle.new(:id(0), :record({attrs => {title => 'No Author', body => '...'}}));
      expect($orphan-article.save).to.be-truthy;
    }
  }

  context 'polymorphic + optional', {
    it 'saves without target', {
      my $bare-attach = BoAttachment.create({name => 'unattached.txt'});
      expect($bare-attach.id).to.be-greater-than(0);
    }

    it 'saves with target', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $a-with = BoAttachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.id).to.be-greater-than(0);
    }

    it 'fills attachable_id', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $a-with = BoAttachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.attrs<attachable_id>).to.eq($alice.id);
    }

    it 'fills attachable_type', {
      my $alice = BoUser.create({fname => 'Alice', lname => 'A'});
      my $a-with = BoAttachment.create({name => 'avatar.png', attachable => $alice});
      expect($a-with.attrs<attachable_type>).to.eq('BoUser');
    }
  }

  context 'polymorphic + default-required', {
    it 'is invalid without target', {
      my $bare-pic = BoPicture.new(:id(0), :record({attrs => {name => 'orphan.png'}}));
      expect($bare-pic.is-invalid).to.be-truthy;
    }

    it 'is invalid when only _id is set', {
      my $half = BoPicture.new(:id(0), :record({attrs => {name => 'half.png', imageable_id => 1}}));
      expect($half.is-invalid).to.be-truthy;
    }
  }

  context 'is-belongs-to-optional predicate', {
    it 'returns False on missing key', {
      expect(BoUser.new(:id(0)).is-belongs-to-optional('user')).to.be-falsy;
    }

    it 'returns True for optional: True', {
      expect(BoPassport.new(:id(0)).is-belongs-to-optional('owner')).to.be-truthy;
    }

    it 'returns False when default-required', {
      expect(BoPage.new(:id(0)).is-belongs-to-optional('user')).to.be-falsy;
    }
  }
}
