use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Instrumentation::Notifications;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

describe 'is-schema-change-sql classifier', {
  if !$adapter.defined {
    pending 'no adapter configured for the classifier';
  } else {
    it 'classifies CREATE as a schema change', {
      expect($adapter.is-schema-change-sql('CREATE TABLE t (id int)')).to.be-truthy;
    }

    it 'classifies ALTER as a schema change', {
      expect($adapter.is-schema-change-sql('  alter table t add column x int')).to.be-truthy;
    }

    it 'classifies DROP as a schema change', {
      expect($adapter.is-schema-change-sql('DROP TABLE t')).to.be-truthy;
    }

    it 'classifies RENAME as a schema change', {
      expect($adapter.is-schema-change-sql('RENAME TABLE a TO b')).to.be-truthy;
    }

    it 'classifies SELECT as a non-schema-change', {
      expect($adapter.is-schema-change-sql('SELECT * FROM t')).to.be-falsy;
    }

    it 'classifies INSERT as a non-schema-change', {
      expect($adapter.is-schema-change-sql('INSERT INTO t(id) VALUES (1)')).to.be-falsy;
    }

    it 'is not fooled by a leading comment', {
      expect($adapter.is-schema-change-sql('/* note */ DROP TABLE t')).to.be-truthy;
    }
  }
}

describe 'adapter schema-cache memoization', {
  if !$has-db {
    pending 'no reachable database for the configured adapter';
  } else {
    before-each {
      $adapter.exec('DROP TABLE IF EXISTS sc_widgets');
      $adapter.ddl-create-table('sc_widgets', [ name => { :string, limit => 64 } ]);
      $adapter.clear-schema-cache;
    }

    after-each {
      try $adapter.exec('DROP TABLE IF EXISTS sc_widgets');
    }

    it 'serves a repeated get-fields from the cache without another query', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      $adapter.get-fields(table => 'sc_widgets');
      my $after-first = @sql.elems;
      $adapter.get-fields(table => 'sc_widgets');

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    it 'serves a repeated column-details from the cache without another query', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      $adapter.column-details(table => 'sc_widgets');
      my $after-first = @sql.elems;
      $adapter.column-details(table => 'sc_widgets');

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    it 'invalidates the cache on a schema change and re-introspects the new column', {
      $adapter.get-fields(table => 'sc_widgets');
      $adapter.ddl-add-column('sc_widgets', 'extra' => { :integer });

      my @names = $adapter.get-fields(table => 'sc_widgets').map(*.[0]);
      expect(@names.first(* eq 'extra').defined).to.be-truthy;
    }

    it 'invalidates the column-details cache on a schema change too', {
      $adapter.column-details(table => 'sc_widgets');
      $adapter.ddl-add-column('sc_widgets', 'extra' => { :integer });

      my @names = $adapter.column-details(table => 'sc_widgets').map(*<name>);
      expect(@names.first(* eq 'extra').defined).to.be-truthy;
    }
  }
}
