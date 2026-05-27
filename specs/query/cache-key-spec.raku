use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS ck_widgets');
  $adapter.ddl-create-table('ck_widgets', [
    name => { :string, limit => 64 },
    qty  => { :integer, default => 0 },
  ]);
  $adapter.ddl-add-timestamps('ck_widgets');

  $adapter.exec('DROP TABLE IF EXISTS ck_gadgets');
  $adapter.ddl-create-table('ck_gadgets', [
    label => { :string, limit => 64 },
  ]);
}

class CkWidget is Model {
  method table-name { 'ck_widgets' }
}
class CkGadget is Model {
  method table-name { 'ck_gadgets' }
}

END {
  if $has-db {
    try $adapter.exec('DROP TABLE IF EXISTS ck_widgets');
    try $adapter.exec('DROP TABLE IF EXISTS ck_gadgets');
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'cache-key', {
  before-each {
    CkWidget.destroy-all if $has-db;
    CkGadget.destroy-all if $has-db;
  }

  context 'fnv1a-hex sanity', {
    it 'of empty string is the FNV-1a 64-bit offset basis', {
      expect(Utils.fnv1a-hex('')).to.eq('cbf29ce484222325');
    }

    it 'of "a" matches the standard reference output', {
      expect(Utils.fnv1a-hex('a')).to.eq('af63dc4c8601ec8c');
    }

    it 'of "foobar" matches the standard reference output', {
      expect(Utils.fnv1a-hex('foobar')).to.eq('85944171f73967e8');
    }

    it 'is case-sensitive', {
      expect(Utils.fnv1a-hex('A')).not.to.eq(Utils.fnv1a-hex('a'));
    }

    it 'output is 16 hex chars', {
      expect(Utils.fnv1a-hex('hello').chars).to.eq(16);
    }
  }

  context 'cache-key on model and relation', {
    it 'is "<table>/query-<16 hex chars>"', {
      expect(CkWidget.cache-key).to.match(/^ 'ck_widgets/query-' <[0..9 a..f]> ** 16 $/);
    }

    it 'changes when WHERE narrows the SQL', {
      expect(CkWidget.cache-key).not.to.eq(CkWidget.where({ qty => 1 }).cache-key);
    }

    it 'matches Model.all.cache-key', {
      expect(CkWidget.cache-key).to.eq(CkWidget.all.cache-key);
    }

    it 'is deterministic for the same relation', {
      expect(CkWidget.where({ qty => 1 }).cache-key).to.eq(CkWidget.where({ qty => 1 }).cache-key);
    }

    it 'namespaces by table', {
      expect(CkWidget.cache-key).not.to.eq(CkGadget.cache-key);
    }
  }

  context 'cache-version with no rows', {
    it 'is "0" when the relation is empty', {
      expect(CkWidget.cache-version).to.eq('0');
    }

    it 'appends "-0" on an empty relation', {
      expect(CkWidget.cache-key-with-version).to.eq(CkWidget.cache-key ~ '-0');
    }
  }

  context 'cache-version after inserts', {
    before-each {
      CkWidget.create({ name => 'Alpha', qty => 1 });
      CkWidget.create({ name => 'Beta',  qty => 2 });
    }

    it 'starts with row count and embeds max(updated_at)', {
      expect(CkWidget.cache-version).to.match(/^ 2 '-' .+ /);
    }

    it 'cache-key-with-version starts with the cache-key', {
      my $k1 = CkWidget.cache-key-with-version;

      expect($k1.starts-with(CkWidget.cache-key ~ '-')).to.be-truthy;
    }

    it 'cache-key-with-version ends with the version', {
      my $v1 = CkWidget.cache-version;
      my $k1 = CkWidget.cache-key-with-version;

      expect($k1.ends-with($v1)).to.be-truthy;
    }

    it 'cache-version changes when a row is added', {
      my $v1 = CkWidget.cache-version;
      CkWidget.create({ name => 'Gamma', qty => 3 });

      expect(CkWidget.cache-version).not.to.eq($v1);
    }
  }

  context 'when the table has no updated_at column', {
    before-each {
      CkGadget.create({ label => 'one' });
    }

    it 'cache-version is undefined', {
      expect(CkGadget.cache-version.defined).to.be-falsy;
    }

    it 'cache-key-with-version falls back to bare cache-key', {
      expect(CkGadget.cache-key-with-version).to.eq(CkGadget.cache-key);
    }
  }

  context 'none short-circuits cache-version', {
    it 'is "0" without querying', {
      expect(CkWidget.none.cache-version).to.eq('0');
    }

    it 'cache-key-with-version appends "-0"', {
      expect(CkWidget.none.cache-key-with-version).to.eq(CkWidget.none.cache-key ~ '-0');
    }
  }

  it 'tracks bound values via the SQL fingerprint', {
    expect(CkWidget.where({ qty => 1 }).cache-key).not.to.eq(CkWidget.where({ qty => 2 }).cache-key);
  }

  it 'cache helpers do not mutate the relation', {
    my $rel = CkWidget.where({ qty => 1 });
    my $sql-before = $rel.to-sql;

    $rel.cache-key;
    $rel.cache-version;
    $rel.cache-key-with-version;

    expect($rel.to-sql).to.eq($sql-before);
  }

  it 'tracks ORDER BY', {
    expect(CkWidget.order('qty').cache-key).not.to.eq(CkWidget.order('name').cache-key);
  }
}
