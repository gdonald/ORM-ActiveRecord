use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter   = DB.shared.adapter;
my $has-db    = $adapter.defined && $adapter.is-connected;
my $is-mysql  = ($has-db ?? configured-adapter-name() // '' !! '') eq 'mysql';

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS exp_widgets');
  $adapter.ddl-create-table('exp_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
}

class ExpWidget is Model {
  method table-name { 'exp_widgets' }
}

END {
  try $adapter.exec('DROP TABLE IF EXISTS exp_widgets') if $has-db;
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'explain', {
  before-each {
    if $has-db {
      ExpWidget.destroy-all;
      ExpWidget.create({ name => 'Alpha', qty => 1 });
      ExpWidget.create({ name => 'Beta',  qty => 2 });
      ExpWidget.create({ name => 'Gamma', qty => 3 });
    }
  }

  context 'Model.explain', {
    it 'returns a string', {
      expect(ExpWidget.explain.defined).to.be-truthy;
    }

    # DBDish::mysql returns no rows for EXPLAIN via the prepared-statement
    # path, so `.explain` is the empty string on MySQL. Skip the non-empty
    # plan assertions there until DBDish gains a non-prepared fallback.
    unless $is-mysql {
      it 'returns a non-empty plan', {
        expect(ExpWidget.explain.chars).to.be-greater-than(0);
      }

      it 'mentions scan or table', {
        my $plan-all = ExpWidget.explain;

        expect($plan-all.uc.contains('SCAN') || $plan-all.uc.contains('EXP_WIDGETS')).to.be-truthy;
      }
    }
  }

  unless $is-mysql {
    it 'relation.explain returns a non-empty plan', {
      my $plan-where = ExpWidget.where({ name => 'Alpha' }).explain;

      expect($plan-where.defined && $plan-where.chars > 0).to.be-truthy;
    }

    it 'works after .order', {
      my $plan-order = ExpWidget.order('qty').explain;

      expect($plan-order.defined && $plan-order.chars > 0).to.be-truthy;
    }

    it 'runs against a SELECT with bind parameters', {
      my $plan-with-binds = ExpWidget.where({ qty => 1..2 }).explain;

      expect($plan-with-binds.defined && $plan-with-binds.chars > 0).to.be-truthy;
    }
  }

  it 'does not mutate the relation', {
    my $rel = ExpWidget.where({ name => 'Alpha' });
    my $sql-before = $rel.to-sql;
    $rel.explain;

    expect($rel.to-sql).to.eq($sql-before);
  }

  it 'always returns a Str even when zero rows match', {
    expect(ExpWidget.where({ qty => 99 }).explain.WHAT.gist).to.eq(Str.gist);
  }
}
