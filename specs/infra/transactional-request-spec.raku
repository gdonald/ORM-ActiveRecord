use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Connection::Registry;
use ORM::ActiveRecord::Testing::Transaction;
use Defaults::NullableColumns;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'a request inside a transactional test', {
  context 'with a connection registry bound the way the database middleware binds one', {
    let(:registry, { ORM::ActiveRecord::Connection::Registry.new });

    it 'finds a row the test created before the request', {
      with-rollback {
        Ward.create({ name => 'Ada', slot => 1, code => 'request-reads-test-row' });

        my $*AR-CONNECTION-REGISTRY = registry;
        LEAVE registry.release-all;

        expect(Ward.find-by({ code => 'request-reads-test-row' })).to.be-truthy;
      }
    }

    it 'checks no pooled connection out of the registry', {
      with-rollback {
        my $*AR-CONNECTION-REGISTRY = registry;
        LEAVE registry.release-all;

        Ward.where({ code => 'request-uses-shared' }).count;

        expect(registry.checked-out-names).to.eq(());
      }
    }

    it 'rolls back a row the request wrote', {
      with-rollback {
        my $*AR-CONNECTION-REGISTRY = registry;
        LEAVE registry.release-all;

        Ward.create({ name => 'Ben', slot => 2, code => 'request-writes-row' });
      }

      expect(Ward.where({ code => 'request-writes-row' }).count).to.eq(0);
    }
  }
}
