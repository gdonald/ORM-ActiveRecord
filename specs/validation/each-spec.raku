use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Errors::X;
use Validation::Each;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'validates-each block validator', {
  before-each { Symphony.destroy-all }
  after-each  { Symphony.destroy-all }

  context 'single attribute', {
    it 'is invalid when name is lowercase', {
      my $e = Symphony.build({name => 'lowercase', score => 1, max_score => 1});
      expect($e.is-invalid).to.be-truthy;
    }

    it 'adds the block message', {
      my $e = Symphony.build({name => 'lowercase', score => 1, max_score => 1});
      $e.is-invalid;
      expect($e.errors.name[0]).to.eq('must start with capital letter');
    }

    it 'is valid when name starts with capital', {
      my $e = Symphony.build({name => 'Capital', score => 1, max_score => 1});
      expect($e.is-valid).to.be-truthy;
    }
  }

  context 'multiple attributes', {
    it 'is invalid when any score is negative', {
      my $m = Fanfare.build({name => 'A', score => -1, max_score => -2});
      expect($m.is-invalid).to.be-truthy;
    }

    it 'applies the block to score', {
      my $m = Fanfare.build({name => 'A', score => -1, max_score => -2});
      $m.is-invalid;
      expect($m.errors.score[0]).to.eq('must not be negative');
    }

    it 'applies the block to max_score', {
      my $m = Fanfare.build({name => 'A', score => -1, max_score => -2});
      $m.is-invalid;
      expect($m.errors.max_score[0]).to.eq('must not be negative');
    }

    it 'is valid when both scores are non-negative', {
      my $m = Fanfare.build({name => 'A', score => 1, max_score => 2});
      expect($m.is-valid).to.be-truthy;
    }
  }
}

describe 'validates-each options', {
  context ':if guard', {
    it 'runs the block when :if is true', {
      my $e = Overture.build({name => 'x', score => 5, max_score => 0});
      expect($e.is-invalid).to.be-truthy;
    }

    it 'skips the block when :if is false', {
      my $e = Overture.build({name => 'x', score => 0, max_score => 0});
      expect($e.is-valid).to.be-truthy;
    }
  }

  context ':unless guard', {
    it 'skips the block when :unless is true', {
      my $e = Interlude.build({name => 'x', score => 5, max_score => 0});
      expect($e.is-valid).to.be-truthy;
    }

    it 'runs the block when :unless is false', {
      my $e = Interlude.build({name => 'x', score => 0, max_score => 0});
      expect($e.is-invalid).to.be-truthy;
    }
  }

  context 'on: context', {
    it 'runs the block under the named context', {
      my $e = Prelude.build({name => 'x', score => 0, max_score => 0});
      expect($e.is-invalid(:context<review>)).to.be-truthy;
    }

    it 'skips the block in the default context', {
      my $e = Prelude.build({name => 'x', score => 0, max_score => 0});
      expect($e.is-valid).to.be-truthy;
    }
  }

  context 'strict', {
    it 'raises X::StrictValidationFailed when the block records an error', {
      my $e = Aria.build({name => 'lowercase', score => 0, max_score => 0});
      my $caught;
      try { $e.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'does not raise when the block records nothing', {
      my $e = Aria.build({name => 'Capital', score => 0, max_score => 0});
      expect($e.is-valid).to.be-truthy;
    }
  }
}
