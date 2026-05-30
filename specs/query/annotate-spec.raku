use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'annotate', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    User.destroy-all;
  }

  it 'appends a /* comment */', {
    my $sql = User.annotate('by reports controller').to-sql;

    expect($sql.contains('/* by reports controller */')).to.be-truthy;
  }

  context 'multiple annotations stack in declaration order', {
    it 'includes the first annotation', {
      my $sql = User.annotate('first').annotate('second').to-sql;

      expect($sql.contains('/* first */')).to.be-truthy;
    }

    it 'includes the second annotation', {
      my $sql = User.annotate('first').annotate('second').to-sql;

      expect($sql.contains('/* second */')).to.be-truthy;
    }

    it 'preserves declaration order', {
      my $sql = User.annotate('first').annotate('second').to-sql;

      expect($sql.index('/* first */') < $sql.index('/* second */')).to.be-truthy;
    }
  }

  context 'annotate does not change result rows', {
    it 'does not affect row count', {
      my @rows = User.annotate('observability').order('fname').all;

      expect(@rows.elems).to.eq(3);
    }

    it 'returns rows in expected order', {
      my @rows = User.annotate('observability').order('fname').all;

      expect(@rows[0].fname).to.eq('Alice');
    }
  }

  it 'composes with where', {
    my @bobs = User.annotate('lookup').where({fname => 'Bob'}).all;

    expect(@bobs.elems == 1 && @bobs[0].fname eq 'Bob').to.be-truthy;
  }

  it 'neutralises embedded comment terminators', {
    my $sql3 = User.annotate('oops */ DROP TABLE users; /*').to-sql;

    expect($sql3.contains('*/ DROP TABLE users; /*')).to.be-falsy;
  }

  context 'optimizer-hints', {
    it 'emits a /*+ ... */ block', {
      my $hint-sql = User.optimizer-hints('MAX_EXECUTION_TIME(1000)').to-sql;

      expect($hint-sql.contains('/*+ MAX_EXECUTION_TIME(1000) */')).to.be-truthy;
    }

    it 'sits directly after SELECT', {
      my $hint-sql = User.optimizer-hints('MAX_EXECUTION_TIME(1000)').to-sql;

      expect($hint-sql).to.match(/'SELECT' \s+ '/*+'/);
    }

    it 'multiple hints share one /*+ ... */ block', {
      my $hint-sql2 = User.optimizer-hints('A', 'B').to-sql;

      expect($hint-sql2.contains('/*+ A B */')).to.be-truthy;
    }

    it 'does not change row count', {
      my @hinted = User.optimizer-hints('NO_INDEX_MERGE(users)').all;

      expect(@hinted.elems).to.eq(3);
    }
  }

  it 'annotate without arguments dies', {
    expect({ User.all.annotate() }).to.raise-error;
  }
}
