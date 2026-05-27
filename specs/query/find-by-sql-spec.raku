use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class FsUser is Model {
  method table-name { 'users' }
}

describe 'find-by-sql / select-all', {
  before-each {
    FsUser.destroy-all;
    FsUser.create({fname => 'Alice', lname => 'Anderson'});
    FsUser.create({fname => 'Bob',   lname => 'Brown'});
    FsUser.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    FsUser.destroy-all;
  }

  context 'find-by-sql with no binds', {
    it 'returns rows', {
      my @rows = FsUser.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows.elems).to.eq(3);
    }

    it 'returns model instances', {
      my @rows = FsUser.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0] ~~ FsUser).to.be-truthy;
    }

    it 'populates attributes from the SELECT result', {
      my @rows = FsUser.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0].fname).to.eq('Alice');
    }

    it 'populates the id', {
      my @rows = FsUser.find-by-sql('SELECT * FROM users ORDER BY fname');

      expect(@rows[0].id).to.be-greater-than(0);
    }
  }

  it 'array form binds parameters', {
    my @bobs = FsUser.find-by-sql(['SELECT * FROM users WHERE fname = ?', 'Bob']);

    expect(@bobs.elems == 1 && @bobs[0].fname eq 'Bob').to.be-truthy;
  }

  it 'variadic form binds parameters', {
    my @bobs2 = FsUser.find-by-sql('SELECT * FROM users WHERE fname = ?', 'Bob');

    expect(@bobs2.elems == 1 && @bobs2[0].fname eq 'Bob').to.be-truthy;
  }

  it 'supports :name binds', {
    my @carols = FsUser.find-by-sql(['SELECT * FROM users WHERE fname = :n', { n => 'Carol' }]);

    expect(@carols.elems == 1 && @carols[0].fname eq 'Carol').to.be-truthy;
  }

  context 'select-all', {
    it 'returns all rows', {
      my @all-rows = FsUser.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows.elems).to.eq(3);
    }

    it 'rows are Hashes', {
      my @all-rows = FsUser.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows[0] ~~ Hash).to.be-truthy;
    }

    it 'hash keys are column names', {
      my @all-rows = FsUser.select-all('SELECT fname, lname FROM users ORDER BY fname');

      expect(@all-rows[0]<fname>).to.eq('Alice');
    }

    it 'array form binds', {
      my @row = FsUser.select-all(['SELECT fname FROM users WHERE lname = ?', 'Brown']);

      expect(@row.elems == 1 && @row[0]<fname> eq 'Bob').to.be-truthy;
    }

    it 'exposes computed columns', {
      my @counted = FsUser.select-all('SELECT count(*) AS n FROM users');

      expect(@counted.elems == 1 && @counted[0]<n>.Int == 3).to.be-truthy;
    }
  }
}
