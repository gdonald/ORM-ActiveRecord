use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use Models::User;
use Models::ShopWidget;
use Models::TenantNote;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'composite primary keys', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  describe 'declaration', {
    it 'reports both key columns in order', {
      expect(ShopWidget.primary-key).to.eq(('shop_id', 'id'));
    }

    it 'knows a two-column key is composite', {
      expect(ShopWidget.has-composite-primary-key).to.be-truthy;
    }

    it 'keeps the single id key for an ordinary model', {
      expect(User.primary-key).to.eq('id');
    }

    it 'reports an ordinary model as not composite', {
      expect(User.has-composite-primary-key).to.be-falsy;
    }
  }

  describe 'finders', {
    before-each {
      ShopWidget.create({shop_id => 1, id => 1, name => 'a', quantity => 10});
      ShopWidget.create({shop_id => 2, id => 1, name => 'b', quantity => 20});
    }

    it 'locates the row matching both columns of a key tuple', {
      expect(ShopWidget.find([1, 1]).attrs<name>).to.eq('a');
    }

    it 'treats the same id under another shop as a different row', {
      expect(ShopWidget.find([2, 1]).attrs<name>).to.eq('b');
    }

    it 'raises when no row matches the composite key', {
      expect({ ShopWidget.find([9, 9]) }).to.throw(X::RecordNotFound);
    }
  }

  describe 'writes scoped by every key column', {
    before-each {
      ShopWidget.create({shop_id => 1, id => 1, name => 'a', quantity => 10});
      ShopWidget.create({shop_id => 2, id => 1, name => 'b', quantity => 20});
    }

    context 'updating one composite-key row', {
      before-each { ShopWidget.find([1, 1]).update({quantity => 99}) }

      it 'lands on the targeted row', {
        expect(ShopWidget.find([1, 1]).attrs<quantity>).to.eq(99);
      }

      it 'leaves the same-id row in the other shop untouched', {
        expect(ShopWidget.find([2, 1]).attrs<quantity>).to.eq(20);
      }
    }

    context 'destroying one composite-key row', {
      before-each { ShopWidget.find([1, 1]).destroy }

      it 'removes the targeted row', {
        expect({ ShopWidget.find([1, 1]) }).to.throw(X::RecordNotFound);
      }

      it 'leaves the same-id row in the other shop in place', {
        expect(ShopWidget.find([2, 1]).attrs<name>).to.eq('b');
      }
    }
  }

  describe 'query-constraints scope writes by extra columns', {
    before-each {
      TenantNote.create({tenant_id => 1, id => 1, body => 'x'});
      TenantNote.create({tenant_id => 2, id => 1, body => 'y'});
    }

    context 'updating a note matching every constraint column', {
      before-each { TenantNote.find-by({tenant_id => 1, id => 1}).update({body => 'x2'}) }

      it 'lands on the matching row', {
        expect(TenantNote.find-by({tenant_id => 1, id => 1}).attrs<body>).to.eq('x2');
      }

      it 'leaves the same-id row in the other tenant untouched', {
        expect(TenantNote.find-by({tenant_id => 2, id => 1}).attrs<body>).to.eq('y');
      }
    }

    it 'scopes a destroy by every constraint column', {
      TenantNote.find-by({tenant_id => 1, id => 1}).destroy;
      expect(TenantNote.find-by({tenant_id => 2, id => 1}).attrs<body>).to.eq('y');
    }
  }
}
