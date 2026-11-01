use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::Account;
use Models::Picture;
use Models::Page;
use Inferred;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'association class inferred from the association name', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'belongs-to', {
    let(:user, { Inferred::User.create({fname => 'Greg', lname => 'Donald'}) });
    let(:page, { Inferred::Page.create({:user(user), name => 'Raku'}) });

    it 'resolves the class from the singular name', {
      expect(Inferred::Page.reflect-on-association('user').klass === Inferred::User).to.be-truthy;
    }

    it 'loads the parent row', {
      expect(Inferred::Page.find(page.id).user.id).to.eq(user.id);
    }
  }

  context 'has-many', {
    let(:user, { Inferred::User.create({fname => 'Greg', lname => 'Donald'}) });
    let(:page, { Inferred::Page.create({:user(user), name => 'Raku'}) });

    it 'resolves the class from the plural name', {
      expect(Inferred::User.reflect-on-association('pages').klass === Inferred::Page).to.be-truthy;
    }

    it 'loads the child rows', {
      page;

      expect(Inferred::User.find(user.id).pages.map(*.id).List).to.eq((page.id,));
    }
  }

  context 'has-one', {
    let(:user,    { Inferred::User.create({fname => 'Greg', lname => 'Donald'}) });
    let(:profile, { Inferred::Profile.create({:user(user), bio => 'Raku'}) });

    it 'resolves the class from the singular name', {
      expect(Inferred::User.reflect-on-association('profile').klass === Inferred::Profile).to.be-truthy;
    }

    it 'loads the child row', {
      profile;

      expect(Inferred::User.find(user.id).profile.id).to.eq(profile.id);
    }
  }

  context 'has-and-belongs-to-many', {
    let(:post, { Inferred::Post.create({title => 'Hello'}) });
    let(:tag,  { Inferred::Tag.create({name => 'raku'}) });

    it 'resolves the class from the plural name', {
      expect(Inferred::Post.reflect-on-association('tags').klass === Inferred::Tag).to.be-truthy;
    }

    it 'loads the linked rows', {
      post.add-tag(tag);

      expect(post.tags.map(*.id).List).to.eq((tag.id,));
    }
  }

  context 'has-many through', {
    let(:user,     { Inferred::User.create({fname => 'Greg', lname => 'Donald'}) });
    let(:magazine, { Inferred::Magazine.create({title => 'Mad'}) });

    it 'resolves the class through the join model', {
      expect(Inferred::User.reflect-on-association('magazines').klass === Inferred::Magazine).to.be-truthy;
    }

    it 'loads the rows through the join model', {
      Inferred::Subscription.create({:user(user), :magazine(magazine)});

      expect(Inferred::User.find(user.id).magazines.map(*.id).List).to.eq((magazine.id,));
    }
  }

  context 'has-many through a dashed join association', {
    let(:cart, { Inferred::Cart.create({name => 'First'}) });
    let(:tag,  { Inferred::Tag.create({name => 'raku'}) });

    it 'resolves the class through the join model', {
      expect(Inferred::Cart.reflect-on-association('tags').klass === Inferred::Tag).to.be-truthy;
    }

    it 'reads the rows from the join model table', {
      Inferred::CartTag.create({:cart(cart), :tag(tag)});

      expect(Inferred::Cart.find(cart.id).tags.map(*.id).List).to.eq((tag.id,));
    }

    it 'writes a join row when a record is added', {
      cart.tags.push(tag);

      expect(Inferred::CartTag.where({cart_id => cart.id, tag_id => tag.id}).count).to.eq(1);
    }

    it 'removes the join row when a record is deleted', {
      Inferred::CartTag.create({:cart(cart), :tag(tag)});
      Inferred::Cart.find(cart.id).tags.delete(tag);

      expect(Inferred::CartTag.where({cart_id => cart.id}).count).to.eq(0);
    }

    it 'joins through the join model table', {
      Inferred::CartTag.create({:cart(cart), :tag(tag)});

      expect(Inferred::Cart.joins(:tags).count).to.eq(1);
    }
  }

  context 'has-one through', {
    let(:user,    { Inferred::User.create({fname => 'Greg', lname => 'Donald'}) });
    let(:account, { Account.create({name => 'Main'}) });

    it 'resolves the class through the intermediate model', {
      expect(Inferred::User.reflect-on-association('account').klass === Account).to.be-truthy;
    }

    it 'loads the row through the intermediate model', {
      Inferred::Profile.create({:user(user), :account(account), bio => 'Raku'});

      expect(Inferred::User.find(user.id).account.id).to.eq(account.id);
    }
  }

  context 'has-many as a polymorphic owner', {
    let(:post, { Inferred::Post.create({title => 'Hello'}) });

    it 'resolves the class from the plural name', {
      expect(Inferred::Post.reflect-on-association('pictures').klass === Picture).to.be-truthy;
    }

    it 'loads the rows', {
      post.pictures.create({name => 'cover'});

      expect(post.pictures.map(*.attrs<name>).List).to.eq(('cover',));
    }
  }

  context 'multi-word names', {
    let(:cart,      { Inferred::Cart.create({name => 'First'}) });
    let(:line-item, { Inferred::LineItem.create({:cart(cart), name => 'Widget'}) });
    let(:note,      { Inferred::LineItemNote.create({:line-item(line-item), body => 'Fragile'}) });

    it 'resolves a dashed plural name to a camel-case class', {
      expect(Inferred::Cart.reflect-on-association('line-items').klass === Inferred::LineItem).to.be-truthy;
    }

    it 'resolves a dashed singular name to a camel-case class', {
      expect(Inferred::LineItemNote.reflect-on-association('line-item').klass === Inferred::LineItem).to.be-truthy;
    }

    it 'loads the child rows of a dashed has-many', {
      line-item;

      expect(Inferred::Cart.find(cart.id).line-items.map(*.id).List).to.eq((line-item.id,));
    }

    it 'stores the dashed belongs-to in an underscored foreign key column', {
      expect(note.attrs<line_item_id>).to.eq(line-item.id);
    }

    it 'finds rows by a dashed belongs-to in a where clause', {
      note;

      expect(Inferred::LineItemNote.where({:line-item(line-item)}).count).to.eq(1);
    }

    it 'requires the parent of a dashed belongs-to', {
      my $orphan = Inferred::LineItemNote.new(:id(0));
      $orphan.is-valid;

      expect($orphan.errors.full-messages.join(' ')).to.match(/'must exist'/);
    }

    it 'loads the parent row of a dashed belongs-to', {
      expect(Inferred::LineItemNote.find(note.id).line-item.id).to.eq(line-item.id);
    }

    it 'reports the underscored foreign key of a dashed belongs-to', {
      expect(Inferred::LineItemNote.reflect-on-association('line-item').foreign-key).to.eq('line_item_id');
    }

    it 'builds the owner foreign key from the snake_cased class name', {
      expect(Inferred::LineItem.reflect-on-association('line-item-notes').foreign-key).to.eq('line_item_id');
    }

    it 'loads the child rows of a multi-word owner', {
      note;

      expect(Inferred::LineItem.find(line-item.id).line-item-notes.map(*.id).List).to.eq((note.id,));
    }
  }

  context 'irregular plurals', {
    it 'resolves people to Person', {
      expect(Inferred::Cart.reflect-on-association('people').klass === Inferred::Person).to.be-truthy;
    }

    it 'resolves categories to Category', {
      expect(Inferred::Cart.reflect-on-association('categories').klass === Inferred::Category).to.be-truthy;
    }

    it 'stores an irregular model in its irregular plural table', {
      my $person = Inferred::Person.create({username => 'greg'});

      expect(Inferred::Person.find($person.id).attrs<username>).to.eq('greg');
    }
  }

  context 'a class loaded after the first instance', {
    it 'is found when the association is used', {
      Inferred::LateOwner.new(:id(0));
      GLOBAL::<LateTarget> := LateTarget;

      expect(Inferred::LateOwner.reflect-on-association('late-target').klass === LateTarget).to.be-truthy;
    }
  }

  context 'the owner package', {
    it 'is searched before GLOBAL', {
      expect(Inferred::User.reflect-on-association('pages').klass === Inferred::Page).to.be-truthy;
    }

    it 'falls back to GLOBAL when the package has no such class', {
      expect(Inferred::Profile.reflect-on-association('account').klass === Account).to.be-truthy;
    }
  }

  context 'an explicit class', {
    it 'wins over the inferred class when given by name', {
      expect(Inferred::Page.reflect-on-association('author').klass === Inferred::User).to.be-truthy;
    }

    it 'wins over the inferred class when given as a type', {
      expect(Inferred::Page.reflect-on-association('writer').klass === Inferred::User).to.be-truthy;
    }
  }

  context 'a name with no matching class', {
    let(:role-named, { Inferred::RoleNamed.new(:id(0)) });
    let(:message,    { (try { role-named.manager; '' }) // $!.message });

    it 'still builds the model', {
      expect(role-named.defined).to.be-truthy;
    }

    it 'dies when the association is used', {
      expect({ role-named.manager }).to.raise-error;
    }

    it 'names the association', {
      expect(message).to.match(/'belongs-to \'manager\''/);
    }

    it 'names the class it looked for', {
      expect(message).to.match(/'Inferred::Manager, Manager'/);
    }

    it 'says to load the class with use', {
      expect(message).to.match(/'Load it with `use`'/);
    }

    it 'shows the GLOBAL binding a model file needs', {
      expect(message).to.match(/'GLOBAL::<Manager> := Manager;'/);
    }

    it 'says to pass class-name for a role name', {
      expect(message).to.match(/'class-name'/);
    }
  }

  context 'an underscored name', {
    let(:message, { (try { Inferred::Underscored.new(:id(0)).line_items; '' }) // $!.message });

    it 'treats the underscore as part of the word', {
      expect(message).to.match(/'\'Line_item\''/);
    }
  }

  context 'many instances of one model class', {
    it 'resolve the class from the first instance', {
      Inferred::CountedCart.new(:id(0));
      Inferred.WHO<CountedItem>:delete;

      expect(Inferred::CountedCart.new(:id(0)).has-manys<counted-items><class>.^name).to.eq('Inferred::CountedItem');
    }

    it 'resolve the class once when the first instances are built concurrently', {
      await (^8).map({ start { Inferred::ConcurrentCart.new(:id(0)) } });
      Inferred.WHO<ConcurrentItem>:delete;

      expect(Inferred::ConcurrentCart.new(:id(0)).has-manys<concurrent-items><class>.^name).to.eq('Inferred::ConcurrentItem');
    }
  }
}
