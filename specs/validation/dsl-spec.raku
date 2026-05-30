use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Dsl;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'validates DSL with multiple attributes', {
  before-each { PhMulti.destroy-all }
  after-each  { PhMulti.destroy-all }

  context 'all three fields invalid', {
    it 'is invalid', {
      my $m = PhMulti.build({name => '', score => 0, max_score => 0});
      expect($m.is-invalid).to.be-truthy;
    }

    it 'aggregated declaration produces presence + length errors on name', {
      my $m = PhMulti.build({name => '', score => 0, max_score => 0});
      $m.is-invalid;
      expect($m.errors.name.elems).to.eq(2);
    }

    it 'reports presence error on score', {
      my $m = PhMulti.build({name => '', score => 0, max_score => 0});
      $m.is-invalid;
      expect($m.errors.score[0]).to.eq('must be present');
    }

    it 'reports presence error on max_score', {
      my $m = PhMulti.build({name => '', score => 0, max_score => 0});
      $m.is-invalid;
      expect($m.errors.max_score[0]).to.eq('must be present');
    }
  }

  context 'all fields valid', {
    it 'is valid', {
      my $m = PhMulti.build({name => 'OK', score => 10, max_score => 20});
      expect($m.is-valid).to.be-truthy;
    }
  }

  context 'short name', {
    it 'is invalid', {
      my $m = PhMulti.build({name => 'Z', score => 1, max_score => 1});
      expect($m.is-invalid).to.be-truthy;
    }

    it 'reports length min message', {
      my $m = PhMulti.build({name => 'Z', score => 1, max_score => 1});
      $m.is-invalid;
      expect($m.errors.name[0]).to.eq('at least 2 characters required');
    }
  }

  context 'long name', {
    it 'reports length max message', {
      my $m = PhMulti.build({name => 'WAY-TOO-LONG', score => 1, max_score => 1});
      $m.is-invalid;
      expect($m.errors.name[0]).to.eq('only 8 characters allowed');
    }
  }
}
