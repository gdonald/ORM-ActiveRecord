use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'find-by-sql / select-all', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    User.destroy-all;
  }

  context 'find-by-sql with no binds', {
    it 'returns rows', {
      my @rows = User.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows.elems).to.eq(3);
    }

    it 'returns model instances', {
      my @rows = User.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0] ~~ User).to.be-truthy;
    }

    it 'populates attributes from the SELECT result', {
      my @rows = User.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0].fname).to.eq('Alice');
    }

    it 'populates the id', {
      my @rows = User.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0].id).to.be-greater-than(0);
    }
  }

  it 'array form binds parameters', {
    my @bobs = User.find-by-sql(['SELECT * FROM users WHERE fname = ?', 'Bob']);

    expect(@bobs.elems == 1 && @bobs[0].fname eq 'Bob').to.be-truthy;
  }

  it 'variadic form binds parameters', {
    my @bobs2 = User.find-by-sql('SELECT * FROM users WHERE fname = ?', 'Bob');

    expect(@bobs2.elems == 1 && @bobs2[0].fname eq 'Bob').to.be-truthy;
  }

  it 'supports :name binds', {
    my @carols = User.find-by-sql(['SELECT * FROM users WHERE fname = :n', { n => 'Carol' }]);

    expect(@carols.elems == 1 && @carols[0].fname eq 'Carol').to.be-truthy;
  }

  context 'select-all', {
    it 'returns all rows', {
      my @all-rows = User.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows.elems).to.eq(3);
    }

    it 'rows are Hashes', {
      my @all-rows = User.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows[0] ~~ Hash).to.be-truthy;
    }

    it 'hash keys are column names', {
      my @all-rows = User.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows[0]<fname>).to.eq('Alice');
    }

    it 'array form binds', {
      my @row = User.select-all(['SELECT fname FROM users WHERE lname = ?', 'Brown']);

      expect(@row.elems == 1 && @row[0]<fname> eq 'Bob').to.be-truthy;
    }

    it 'exposes computed columns', {
      my @counted = User.select-all('SELECT count(*) AS n FROM users');

      expect(@counted.elems == 1 && @counted[0]<n>.Int == 3).to.be-truthy;
    }
  }
}
