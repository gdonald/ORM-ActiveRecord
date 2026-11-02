use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use Defaults::NullableColumns;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'calling a method a model does not define', {
  context 'on the model class', {
    it 'raises X::Method::NotFound', {
      expect({ Ward.for-tenant(1) }).to.throw(X::Method::NotFound);
    }

    it 'names the method in the error', {
      expect((try Ward.for-tenant(1)) // $!.method).to.eq('for-tenant');
    }

    it 'names the model in the error', {
      expect((try Ward.for-tenant(1)) // $!.typename).to.eq('Defaults::NullableColumns::Ward');
    }
  }

  context 'on a model instance', {
    let(:ward, { Ward.build({ name => 'Ada', slot => 1, code => 'W1' }) });

    it 'raises X::Method::NotFound', {
      expect({ ward.for-tenant(1) }).to.throw(X::Method::NotFound);
    }

    it 'names the method in the error', {
      expect((try ward.for-tenant(1)) // $!.method).to.eq('for-tenant');
    }

    it 'names the model in the error', {
      expect((try ward.for-tenant(1)) // $!.typename).to.eq('Defaults::NullableColumns::Ward');
    }
  }
}
