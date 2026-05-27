use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AnUser is Model {
  method table-name { 'users' }
}

describe 'annotate', {
  before-each {
    AnUser.destroy-all;
    AnUser.create({fname => 'Alice', lname => 'Anderson'});
    AnUser.create({fname => 'Bob',   lname => 'Brown'});
    AnUser.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    AnUser.destroy-all;
  }

  it 'appends a /* comment */', {
    my $sql = AnUser.annotate('by reports controller').to-sql;

    expect($sql.contains('/* by reports controller */')).to.be-truthy;
  }

  context 'multiple annotations stack in declaration order', {
    it 'includes the first annotation', {
      my $sql = AnUser.annotate('first').annotate('second').to-sql;

      expect($sql.contains('/* first */')).to.be-truthy;
    }

    it 'includes the second annotation', {
      my $sql = AnUser.annotate('first').annotate('second').to-sql;

      expect($sql.contains('/* second */')).to.be-truthy;
    }

    it 'preserves declaration order', {
      my $sql = AnUser.annotate('first').annotate('second').to-sql;

      expect($sql.index('/* first */') < $sql.index('/* second */')).to.be-truthy;
    }
  }

  context 'annotate does not change result rows', {
    it 'does not affect row count', {
      my @rows = AnUser.annotate('observability').order('fname').all;

      expect(@rows.elems).to.eq(3);
    }

    it 'returns rows in expected order', {
      my @rows = AnUser.annotate('observability').order('fname').all;

      expect(@rows[0].fname).to.eq('Alice');
    }
  }

  it 'composes with where', {
    my @bobs = AnUser.annotate('lookup').where({fname => 'Bob'}).all;

    expect(@bobs.elems == 1 && @bobs[0].fname eq 'Bob').to.be-truthy;
  }

  it 'neutralises embedded comment terminators', {
    my $sql3 = AnUser.annotate('oops */ DROP TABLE users; /*').to-sql;

    expect($sql3.contains('*/ DROP TABLE users; /*')).to.be-falsy;
  }

  context 'optimizer-hints', {
    it 'emits a /*+ ... */ block', {
      my $hint-sql = AnUser.optimizer-hints('MAX_EXECUTION_TIME(1000)').to-sql;

      expect($hint-sql.contains('/*+ MAX_EXECUTION_TIME(1000) */')).to.be-truthy;
    }

    it 'sits directly after SELECT', {
      my $hint-sql = AnUser.optimizer-hints('MAX_EXECUTION_TIME(1000)').to-sql;

      expect($hint-sql).to.match(/'SELECT' \s+ '/*+'/);
    }

    it 'multiple hints share one /*+ ... */ block', {
      my $hint-sql2 = AnUser.optimizer-hints('A', 'B').to-sql;

      expect($hint-sql2.contains('/*+ A B */')).to.be-truthy;
    }

    it 'does not change row count', {
      my @hinted = AnUser.optimizer-hints('NO_INDEX_MERGE(users)').all;

      expect(@hinted.elems).to.eq(3);
    }
  }

  it 'annotate without arguments dies', {
    expect({ AnUser.all.annotate() }).to.raise-error;
  }
}
