use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::WorkerDb;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

# Neutralize any per-worker overlay the harness set, so tests control it.
%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;

describe 'worker-index', {
  it 'is undefined when BEHAVE_WORKER_INDEX is unset', {
    temp %*ENV<BEHAVE_WORKER_INDEX>;
    %*ENV<BEHAVE_WORKER_INDEX>:delete;

    expect(worker-index().defined).to.be-falsy;
  }

  it 'returns the integer when BEHAVE_WORKER_INDEX is set', {
    temp %*ENV<BEHAVE_WORKER_INDEX> = '3';

    expect(worker-index()).to.eq(3);
  }

  it 'is undefined when BEHAVE_WORKER_INDEX is non-numeric', {
    temp %*ENV<BEHAVE_WORKER_INDEX> = 'nope';

    expect(worker-index().defined).to.be-falsy;
  }
}

describe 'worker-count', {
  it 'is 1 when BEHAVE_WORKER_COUNT is unset', {
    temp %*ENV<BEHAVE_WORKER_COUNT>;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    expect(worker-count()).to.eq(1);
  }

  it 'returns the integer when BEHAVE_WORKER_COUNT is set', {
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(worker-count()).to.eq(4);
  }
}

describe 'per-worker-dbs-active', {
  it 'is true for a behave parallel worker (index set, count > 1)', {
    temp %*ENV<BEHAVE_WORKER_INDEX> = '2';
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(per-worker-dbs-active()).to.be-truthy;
  }

  it 'is false in serial mode (count 1)', {
    temp %*ENV<BEHAVE_WORKER_INDEX> = '0';
    temp %*ENV<BEHAVE_WORKER_COUNT> = '1';

    expect(per-worker-dbs-active()).to.be-falsy;
  }

  it 'is false outside behave (no index)', {
    temp %*ENV<BEHAVE_WORKER_INDEX>;
    %*ENV<BEHAVE_WORKER_INDEX>:delete;
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(per-worker-dbs-active()).to.be-falsy;
  }
}

describe 'apply-worker-suffix', {
  context 'postgres / mysql named connections', {
    it 'suffixes the pg name', {
      expect(apply-worker-suffix({ adapter => 'pg', name => 'ar_test' }, 2)<name>)
        .to.eq('ar_test_2');
    }

    it 'suffixes the mysql name', {
      expect(apply-worker-suffix({ adapter => 'mysql', name => 'ar_test' }, 2)<name>)
        .to.eq('ar_test_2');
    }

    it 'falls back to the database key when name is absent', {
      expect(apply-worker-suffix({ adapter => 'pg', database => 'ar_test' }, 5)<database>)
        .to.eq('ar_test_5');
    }
  }

  context 'sqlite', {
    it 'suffixes a file path before the extension', {
      expect(apply-worker-suffix({ adapter => 'sqlite', database => 'db/test.sqlite3' }, 3)<database>)
        .to.eq('db/test_3.sqlite3');
    }

    it 'appends to a path with no extension', {
      expect(apply-worker-suffix({ adapter => 'sqlite', name => 'db/test' }, 3)<name>)
        .to.eq('db/test_3');
    }

    it 'leaves :memory: unchanged', {
      expect(apply-worker-suffix({ adapter => 'sqlite', database => ':memory:' }, 3)<database>)
        .to.eq(':memory:');
    }
  }

  context 'edge cases', {
    it 'leaves an empty name unchanged', {
      expect(apply-worker-suffix({ adapter => 'pg', name => '' }, 1)<name>)
        .to.eq('');
    }
  }
}

describe 'DB.read-config worker overlay', {
  it 'suffixes the database name for a parallel worker', {
    temp %*ENV<DATABASE_URL>        = 'postgres://u@localhost/ar_test';
    temp %*ENV<BEHAVE_WORKER_INDEX> = '2';
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(DB.read-config<name>).to.eq('ar_test_2');
  }

  it 'suffixes by the worker index directly', {
    temp %*ENV<DATABASE_URL>        = 'postgres://u@localhost/ar_test';
    temp %*ENV<BEHAVE_WORKER_INDEX> = '3';
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(DB.read-config<name>).to.eq('ar_test_3');
  }

  it 'leaves the database name untouched in serial mode (count 1)', {
    temp %*ENV<DATABASE_URL>        = 'postgres://u@localhost/ar_test';
    temp %*ENV<BEHAVE_WORKER_INDEX> = '2';
    temp %*ENV<BEHAVE_WORKER_COUNT> = '1';

    expect(DB.read-config<name>).to.eq('ar_test');
  }
}
