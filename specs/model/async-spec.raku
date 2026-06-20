use lib 'lib';
use BDD::Behave;
use DBIish;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AsyncGizmo is Model {
  method table-name { 'async_gizmos' }
}

GLOBAL::<AsyncGizmo> := AsyncGizmo;

%*ENV<BEHAVE_WORKER_INDEX>:delete;
%*ENV<BEHAVE_WORKER_COUNT>:delete;
%*ENV<DATABASE_URL> = "sqlite:" ~ $*TMPDIR.add("async-spec-{$*PID}-{(now * 1e6).Int}.sqlite3").Str;
DB.set-shared(Nil);

DB.shared.adapter.ddl-create-table('async_gizmos', [ name => { :string, limit => 32 }, qty => { :integer } ]);
AsyncGizmo.create({ name => 'a', qty => 1 });
AsyncGizmo.create({ name => 'b', qty => 2 });
AsyncGizmo.create({ name => 'c', qty => 3 });

describe 'async queries', {
  it 'load-async returns a Promise of the records', {
    my $promise = AsyncGizmo.all.load-async;

    aggregate-failures {
      expect($promise ~~ Promise).to.be-truthy;
      expect((await $promise).elems).to.eq(3);
    }
  }

  it 'rebinds loaded records to the shared connection', {
    my @records = await AsyncGizmo.all.load-async;
    my $first   = @records.sort(*.attrs<qty>).first;

    aggregate-failures {
      expect($first.is-persisted).to.be-truthy;
      expect($first.reload.attrs<name>).to.eq('a');
    }
  }

  it 'resolves aggregations asynchronously', {
    aggregate-failures {
      expect(await AsyncGizmo.all.count-async).to.eq(3);
      expect(await AsyncGizmo.all.sum-async('qty')).to.eq(6);
      expect(await AsyncGizmo.where({qty => 2}).count-async).to.eq(1);
    }
  }

  it 'resolves pluck and pick asynchronously', {
    aggregate-failures {
      expect((await AsyncGizmo.all.pluck-async('name')).sort.join(',')).to.eq('a,b,c');
      expect(await AsyncGizmo.where({qty => 3}).pick-async('name')).to.eq('c');
    }
  }

  it 'resolves find-by-sql-async', {
    my @found = await AsyncGizmo.find-by-sql-async('SELECT * FROM async_gizmos WHERE qty >= ?', 2);
    expect(@found.elems).to.eq(2);
  }
}
