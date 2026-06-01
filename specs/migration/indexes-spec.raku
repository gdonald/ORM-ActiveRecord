use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Schema::Migration;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter   = DB.shared.adapter;
my $has-db    = $adapter.defined && $adapter.is-connected;

sub adapter-kind(--> Str) {
  return 'none' without $adapter;
  given $adapter.^name {
    when /Pg/     { 'pg' }
    when /MySql/  { 'mysql' }
    when /Sqlite/ { 'sqlite' }
    default       { 'unknown' }
  }
}

my $kind      = adapter-kind();
my $is-pg     = $kind eq 'pg';
my $is-sqlite = $kind eq 'sqlite';
my $is-mysql  = $kind eq 'mysql';

sub table-exists($name) {
  ?$adapter.get-table-names.list.grep({ $_ eq $name }).elems;
}

sub index-exists($name) {
  my $rows = do given $kind {
    when 'pg'     { $adapter.exec("SELECT 1 FROM pg_indexes WHERE indexname = '$name'") }
    when 'mysql'  { $adapter.exec("SELECT 1 FROM information_schema.statistics WHERE table_schema = DATABASE() AND index_name = '$name'") }
    when 'sqlite' { $adapter.exec("SELECT 1 FROM sqlite_master WHERE type='index' AND name='$name'") }
    default       { [] }
  };
  ?$rows.elems;
}

# The CREATE INDEX definition text, where the adapter exposes it. Used to
# assert that clauses (USING / WHERE / INCLUDE / opclass / DESC) landed.
sub index-def($name --> Str) {
  my $rows = do given $kind {
    when 'pg'     { $adapter.exec("SELECT indexdef FROM pg_indexes WHERE indexname = '$name'") }
    when 'sqlite' { $adapter.exec("SELECT sql FROM sqlite_master WHERE type='index' AND name='$name'") }
    default       { [] }
  };
  ($rows.elems && $rows[0][0].defined) ?? $rows[0][0].Str !! '';
}

my @test-tables = <_idx_users>;

sub cleanup-tables {
  for @test-tables -> $t {
    try { $adapter.ddl-drop-table($t) if table-exists($t) }
  }
}

class CreateIdxUsers is Migration {
  method change {
    self.create-table: '_idx_users', [
      email     => { :string, limit => 64 },
      label     => { :string, limit => 64 },
      active    => { :integer },
      tenant_id => { :integer },
      score     => { :integer },
    ];
  }
}

class AddCompositeIndex is Migration {
  method change {
    self.add-index: '_idx_users', <tenant_id email>;
  }
}

class AddUniqueNamedIndex is Migration {
  method change {
    self.add-index: '_idx_users', :email, unique => True, name => 'uniq_user_email';
  }
}

class AddSingleIndex is Migration {
  method change {
    self.add-index: '_idx_users', :score;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'migration indexes', :order<defined>, {
  if !$has-db { pending 'no database connection available'; }

  before-all { if $has-db { cleanup-tables; CreateIdxUsers.new.up } }
  after-all  { if $has-db { cleanup-tables } }

  context 'composite index over multiple columns', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { AddCompositeIndex.new.up } }

      it 'creates <table>_<col1>_<col2>_idx', {
        expect(index-exists('_idx_users_tenant_id_email_idx')).to.be-truthy;
      }
    }

    context 'after down (auto-inverts to remove-index)', :order<defined>, {
      before-all { if $has-db { AddCompositeIndex.new.down } }

      it 'removes the composite index', {
        expect(index-exists('_idx_users_tenant_id_email_idx')).to.be-falsy;
      }
    }
  }

  context 'unique index with an explicit name', :order<defined>, {
    before-all { if $has-db { AddUniqueNamedIndex.new.up } }
    after-all  { if $has-db { AddUniqueNamedIndex.new.down } }

    it 'creates the named index', {
      expect(index-exists('uniq_user_email')).to.be-truthy;
    }

    it 'enforces uniqueness on the column', {
      $adapter.exec("INSERT INTO _idx_users (email) VALUES ('dup\@x.com')");
      expect({ $adapter.exec("INSERT INTO _idx_users (email) VALUES ('dup\@x.com')") }).to.raise-error;
    }
  }

  context 'single-column index with a derived name', :order<defined>, {
    context 'after up', :order<defined>, {
      before-all { if $has-db { AddSingleIndex.new.up } }

      it 'creates <table>_<col>_idx', {
        expect(index-exists('_idx_users_score_idx')).to.be-truthy;
      }
    }

    context 'after down', :order<defined>, {
      before-all { if $has-db { AddSingleIndex.new.down } }

      it 'removes the derived-name index', {
        expect(index-exists('_idx_users_score_idx')).to.be-falsy;
      }
    }
  }

  # Partial (WHERE) indexes: PostgreSQL and SQLite.
  my &partial-group = ($is-pg || $is-sqlite) ?? &context !! &xcontext;

  partial-group 'partial / conditional index (where:)', :order<defined>, {
    if !($is-pg || $is-sqlite) { pending 'partial indexes are PostgreSQL / SQLite only'; }

    my class AddPartial is Migration {
      method change {
        self.add-index: '_idx_users', :score,
          where => 'score > 0',
          name  => 'idx_users_positive_score';
      }
    }

    before-all { if $is-pg || $is-sqlite { AddPartial.new.up } }
    after-all  { if $is-pg || $is-sqlite { AddPartial.new.down } }

    it 'creates the index', {
      expect(index-exists('idx_users_positive_score')).to.be-truthy;
    }

    it 'records the WHERE predicate', {
      expect(index-def('idx_users_positive_score').lc).to.match(/'where'/);
    }
  }

  # Expression indexes: PostgreSQL and SQLite.
  my &expr-group = ($is-pg || $is-sqlite) ?? &context !! &xcontext;

  expr-group 'expression index', :order<defined>, {
    if !($is-pg || $is-sqlite) { pending 'expression index spec covers PostgreSQL / SQLite'; }

    my class AddExpr is Migration {
      method change {
        self.add-index: '_idx_users',
          expression => 'lower(email)',
          name       => 'idx_users_lower_email';
      }
    }

    before-all { if $is-pg || $is-sqlite { AddExpr.new.up } }
    after-all  { if $is-pg || $is-sqlite { AddExpr.new.down } }

    it 'creates the expression index', {
      expect(index-exists('idx_users_lower_email')).to.be-truthy;
    }

    it 'records the lower(email) expression', {
      expect(index-def('idx_users_lower_email').lc).to.match(/'lower'/);
    }
  }

  # Access method, covering, concurrency, and operator-class clauses are
  # PostgreSQL-specific in this spec.
  my &pg-group = $is-pg ?? &context !! &xcontext;

  pg-group 'PostgreSQL index clauses', :order<defined>, {
    if !$is-pg { pending 'these index clauses are exercised on PostgreSQL'; }

    context 'using: btree', :order<defined>, {
      my class AddUsing is Migration {
        method change {
          self.add-index: '_idx_users', :label,
            using => 'btree',
            name  => 'idx_users_label_btree';
        }
      }

      before-all { if $is-pg { AddUsing.new.up } }
      after-all  { if $is-pg { AddUsing.new.down } }

      it 'creates the index with the access method', {
        expect(index-def('idx_users_label_btree').lc).to.match(/'using btree'/);
      }
    }

    context 'include: covering columns', :order<defined>, {
      my class AddCovering is Migration {
        method change {
          self.add-index: '_idx_users', :tenant_id,
            include => <email>,
            name    => 'idx_users_tenant_covering';
        }
      }

      before-all { if $is-pg { AddCovering.new.up } }
      after-all  { if $is-pg { AddCovering.new.down } }

      it 'records the INCLUDE clause', {
        expect(index-def('idx_users_tenant_covering').lc).to.match(/'include'/);
      }
    }

    context 'algorithm: concurrently', :order<defined>, {
      my class AddConcurrent is Migration {
        method change {
          self.add-index: '_idx_users', :active,
            algorithm => 'concurrently',
            name      => 'idx_users_active_conc';
        }
      }

      before-all { if $is-pg { AddConcurrent.new.up } }
      after-all  { if $is-pg { AddConcurrent.new.down } }

      it 'creates the index concurrently', {
        expect(index-exists('idx_users_active_conc')).to.be-truthy;
      }
    }

    context 'opclass: per-column operator class', :order<defined>, {
      my class AddOpclass is Migration {
        method change {
          self.add-index: '_idx_users', :email,
            opclass => 'text_pattern_ops',
            name    => 'idx_users_email_pattern';
        }
      }

      before-all { if $is-pg { AddOpclass.new.up } }
      after-all  { if $is-pg { AddOpclass.new.down } }

      it 'records the operator class', {
        expect(index-def('idx_users_email_pattern').lc).to.match(/'text_pattern_ops'/);
      }
    }
  }

  # Unsupported clauses raise a clear error on the adapters that lack them.
  my &sqlite-group = $is-sqlite ?? &context !! &xcontext;

  sqlite-group 'SQLite rejects unsupported clauses', :order<defined>, {
    if !$is-sqlite { pending 'SQLite-only guard checks'; }

    my class AddUsingSqlite is Migration {
      method change {
        self.add-index: '_idx_users', :label, using => 'btree';
      }
    }

    it 'raises for using:', {
      expect({ AddUsingSqlite.new.up }).to.raise-error;
    }
  }

  my &mysql-group = $is-mysql ?? &context !! &xcontext;

  mysql-group 'MySQL rejects unsupported clauses', :order<defined>, {
    if !$is-mysql { pending 'MySQL-only guard checks'; }

    my class AddWhereMysql is Migration {
      method change {
        self.add-index: '_idx_users', :score, where => 'score > 0';
      }
    }

    it 'raises for where:', {
      expect({ AddWhereMysql.new.up }).to.raise-error;
    }
  }
}
