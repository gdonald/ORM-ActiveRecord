use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

my $p1 = $has-db ?? DB.shared.bind-placeholder(1) !! Nil;
my $p2 = $has-db ?? DB.shared.bind-placeholder(2) !! Nil;

describe 'DB.sanitize-sql', {
  if !$has-db {
    pending 'no DB connection';
  } else {
    context 'positional ? binds', {
      my $a;

      before-each {
        $a = DB.shared.sanitize-sql-array(['name = ? AND age = ?', 'Bob', 30]);
      }

      it 'produces adapter placeholders in order', {
        expect($a.sql).to.eq("name = $p1 AND age = $p2");
      }

      it 'captures two positional binds', {
        expect($a.binds.elems).to.eq(2);
      }

      it 'captures the first positional bind', {
        expect($a.binds[0]).to.eq('Bob');
      }

      it 'captures the second positional bind', {
        expect($a.binds[1]).to.eq(30);
      }
    }

    context 'named template binds', {
      my $b;

      before-each {
        $b = DB.shared.sanitize-sql-array(['name = :name AND age = :age', { name => 'Bob', age => 30 }]);
      }

      it 'substitutes named templates with adapter placeholders', {
        expect($b.sql).to.match(/^ 'name = ' .+? ' AND age = ' .+? $/);
      }

      it 'captures two named binds', {
        expect($b.binds.elems).to.eq(2);
      }
    }

    context 'string literals pass through verbatim', {
      my $c;

      before-each {
        $c = DB.shared.sanitize-sql-array([q{name = ? AND label = '???' AND tag = ':notbound'}, 'Bob']);
      }

      it 'leaves literal content unchanged', {
        expect($c.sql).to.eq(qq{name = $p1 AND label = '???' AND tag = ':notbound'});
      }

      it 'only the unquoted ? consumed a bind', {
        expect($c.binds.elems).to.eq(1);
      }

      it 'captured the correct bind', {
        expect($c.binds[0]).to.eq('Bob');
      }
    }

    context 'escaped quotes inside literal', {
      my $d;

      before-each {
        $d = DB.shared.sanitize-sql-array([q{name = ? AND note = 'O''Neill''s ?'}, 'Bob']);
      }

      it 'preserves the literal', {
        expect($d.sql).to.eq(qq{name = $p1 AND note = 'O''Neill''s ?'});
      }

      it 'consumed only one bind despite ? inside literal', {
        expect($d.binds.elems).to.eq(1);
      }
    }

    context 'arity mismatches raise', {
      it 'dies on too few positional binds', {
        expect({ DB.shared.sanitize-sql-array(['name = ? AND age = ?', 'Bob']) }).to.raise-error;
      }

      it 'dies on too many positional binds', {
        expect({ DB.shared.sanitize-sql-array(['name = ?', 'Bob', 'extra']) }).to.raise-error;
      }

      it 'dies on a missing named bind', {
        expect({ DB.shared.sanitize-sql-array(['name = :name', { other => 'x' }]) }).to.raise-error;
      }

      it 'dies when mixing ? with named binds', {
        expect({ DB.shared.sanitize-sql-array(['name = ? AND age = :age', 'Bob']) }).to.raise-error;
      }
    }

    context 'sanitize-sql with a Str dispatches to passthrough', {
      my $e;

      before-each {
        $e = DB.shared.sanitize-sql('SELECT 1');
      }

      it 'preserves the SQL', {
        expect($e.sql).to.eq('SELECT 1');
      }

      it 'produces no binds', {
        expect($e.binds.elems).to.eq(0);
      }
    }

    context 'sanitized statement round-trips through the DB', {
      it 'returns the bound value unchanged', {
        my $f = DB.shared.sanitize-sql-array(['SELECT ? AS x', q{O'Neill}]);
        my @rows = DB.shared.exec-stmt($f);

        expect(@rows[0][0]).to.eq(q{O'Neill});
      }
    }
  }
}
