use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::With;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'validates-with', {
  before-each { Cabaret.destroy-all }
  after-each  { Cabaret.destroy-all }

  context 'banned name', {
    it 'is invalid', {
      my $w = Cabaret.build({name => 'Evil', score => 5, max_score => 10});
      expect($w.is-invalid).to.be-truthy;
    }

    it 'runs the instance validator', {
      my $w = Cabaret.build({name => 'Evil', score => 5, max_score => 10});
      $w.is-invalid;
      expect($w.errors.base[0]).to.eq("'Evil' is not allowed");
    }
  }

  context 'class + options validator', {
    it 'triggers when score exceeds cap', {
      my $w = Cabaret.build({name => 'OK', score => 500, max_score => 1000});
      expect($w.is-invalid).to.be-truthy;
    }

    it 'forwards options to new()', {
      my $w = Cabaret.build({name => 'OK', score => 500, max_score => 1000});
      $w.is-invalid;
      expect($w.errors.score[0]).to.eq('score exceeds cap of 50');
    }
  }

  context 'clean record', {
    it 'is valid', {
      my $w = Cabaret.build({name => 'OK', score => 5, max_score => 10});
      expect($w.is-valid).to.be-truthy;
    }

    it 'has no base error', {
      my $w = Cabaret.build({name => 'OK', score => 5, max_score => 10});
      $w.is-valid;
      expect($w.errors.base).to.be-falsy;
    }
  }
}
