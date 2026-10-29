use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Log;

my %saved-env = %*ENV;
my @captured;

sub sql-logged(--> Bool) {
  Log.sql(sql => 'SELECT 1');
  so @captured.elems;
}

describe 'SQL log switch', {
  before-each {
    %*ENV<DISABLE_SQL_LOG DISABLE-SQL-LOG BEHAVE_WORKER_COUNT RAKU_ENV DATABASE_URL>:delete;
    %*ENV<AR_ENV> = 'development';

    Log.reset;
    @captured = [];
    Log.set-sink(-> $line, $level { @captured.push: $line });
  }

  after-each {
    %*ENV = %saved-env;
    Log.reset;
  }

  context 'in the development environment', {
    it 'logs SQL', {
      expect(sql-logged()).to.be-truthy;
    }
  }

  context 'in the test environment', {
    before-each { %*ENV<AR_ENV> = 'test' }

    it 'does not log SQL', {
      expect(sql-logged()).to.be-falsy;
    }

    context 'with sql-log turned on', {
      before-each { Log.set-sql-log(True) }

      it 'logs SQL', {
        expect(sql-logged()).to.be-truthy;
      }
    }

    context 'with sql-log turned on through configure', {
      before-each { Log.configure(sql-log => True) }

      it 'logs SQL', {
        expect(sql-logged()).to.be-truthy;
      }
    }

    context 'with sql-log turned on and then reset', {
      before-each {
        Log.set-sql-log(True);
        Log.reset;
        Log.set-sink(-> $line, $level { @captured.push: $line });
      }

      it 'does not log SQL', {
        expect(sql-logged()).to.be-falsy;
      }
    }

    context 'with sql-log set to true in the connection logging config', {
      my $tmp = $*TMPDIR.add("ar-sql-log-switch-spec-{$*PID}");

      before-each {
        $tmp.add('config').mkdir;
        $tmp.add('config/application.json').spurt: q:to/JSON/;
{
  "test": {
    "primary": {
      "adapter": "sqlite",
      "name": ":memory:",
      "logging": { "sql-log": true }
    }
  }
}
JSON

        my $db = indir $tmp, { DB.new };
        $db.disconnect;
      }

      after-each {
        $tmp.add('config/application.json').unlink;
        $tmp.add('config').rmdir;
        $tmp.rmdir;
      }

      it 'logs SQL', {
        expect(sql-logged()).to.be-truthy;
      }
    }
  }

  context 'under a behave worker in the development environment', {
    before-each { %*ENV<BEHAVE_WORKER_COUNT> = '2' }

    it 'does not log SQL', {
      expect(sql-logged()).to.be-falsy;
    }
  }

  context 'with DISABLE_SQL_LOG set', {
    before-each { %*ENV<DISABLE_SQL_LOG> = '1' }

    it 'does not log SQL', {
      expect(sql-logged()).to.be-falsy;
    }

    context 'and sql-log turned on', {
      before-each { Log.set-sql-log(True) }

      it 'does not log SQL', {
        expect(sql-logged()).to.be-falsy;
      }
    }
  }

  context 'with the hyphenated DISABLE-SQL-LOG set', {
    before-each { %*ENV<DISABLE-SQL-LOG> = '1' }

    it 'does not log SQL', {
      expect(sql-logged()).to.be-falsy;
    }
  }
}
