use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;

describe 'generated SQL text', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  # Raku hash order is not stable across hash instances, so the same conditions
  # built twice can enumerate their keys either way round. Both the prepared
  # statement cache and the query cache are keyed on SQL text, so an unstable
  # order would multiply cache entries and miss on every repeat.
  let(:columns-of, {
    -> $sql {
      $sql.comb(/ <[a..z_]>+ ' ='/).map(*.subst(/' ='/, '')).list;
    }
  });

  context 'a WHERE clause', {
    it 'emits the same text for conditions built twice', {
      my $first  = User.where({ fname => 'a', lname => 'b' }).to-sql;
      my $second = User.where({ fname => 'a', lname => 'b' }).to-sql;

      expect($first).to.eq($second);
    }

    it 'emits the columns in a fixed order whichever way they are given', {
      my $one = User.where({ fname => 'a', lname => 'b' }).to-sql;
      my $two = User.where({ lname => 'b', fname => 'a' }).to-sql;

      expect($one).to.eq($two);
    }

    it 'orders the columns by name', {
      my $sql = User.where({ lname => 'b', fname => 'a' }).to-sql;

      expect($sql.index('fname')).to.be-less-than($sql.index('lname'));
    }
  }

  context 'an UPDATE SET clause', {
    let(:name-types, { %( fname => 'character varying', lname => 'character varying' ) });

    let(:stmt, {
      $adapter.build-update(
        :table('users'),
        :id(1),
        :attrs(%( lname => 'b', fname => 'a' )),
        :types(name-types),
      );
    });

    it 'orders the assigned columns by name', {
      expect(columns-of()(stmt.sql).grep({ $_ eq 'fname' | 'lname' }).list).to.eq(('fname', 'lname'));
    }

    it 'emits the same text for the same columns given the other way round', {
      my $other = $adapter.build-update(
        :table('users'),
        :id(1),
        :attrs(%( fname => 'a', lname => 'b' )),
        :types(name-types),
      );

      expect(stmt.sql).to.eq($other.sql);
    }
  }

  context 'a multi-row INSERT', {
    # A hash written inline in a list flattens into its pairs, so each row is
    # pushed as one element.
    let(:one-row, { my @rows; @rows.push: %( lname => 'b', fname => 'a' ); @rows });
    let(:same-row-reversed, { my @rows; @rows.push: %( fname => 'a', lname => 'b' ); @rows });

    it 'orders its column list by name', {
      my $stmt = $adapter.build-insert-many(:table('users'), :rows(one-row));

      expect($stmt.sql.index('fname')).to.be-less-than($stmt.sql.index('lname'));
    }

    it 'emits the same text whichever way the row is given', {
      my $one = $adapter.build-insert-many(:table('users'), :rows(one-row));
      my $two = $adapter.build-insert-many(:table('users'), :rows(same-row-reversed));

      expect($one.sql).to.eq($two.sql);
    }
  }

  context 'a single-row INSERT', {
    it 'orders its column list by name', {
      my $stmt = $adapter.build-insert(:table('users'), :attrs(%( lname => 'b', fname => 'a' )));

      expect($stmt.sql.index('fname')).to.be-less-than($stmt.sql.index('lname'));
    }
  }

  context 'a counter update', {
    it 'orders its counters by name', {
      my $stmt = $adapter.build-update-counters-where(
        :table('users'),
        :counters(%( zeta => 1, alpha => 1 )),
        :where(%( id => 1 )),
      );

      expect($stmt.sql.index('alpha')).to.be-less-than($stmt.sql.index('zeta'));
    }
  }
}
