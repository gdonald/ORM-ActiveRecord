use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Errors::X;
use Validation::Strict;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'strict validation raises X::StrictValidationFailed', {
  before-each { Spectacle.destroy-all }
  after-each  { Spectacle.destroy-all }

  context 'when valid', {
    it 'does not raise', {
      my $ev = Spectacle.build({name => 'OK', score => 1});
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'when invalid', {
    it 'raises an exception', {
      my $ev = Spectacle.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.defined).to.be-truthy;
    }

    it 'raises X::StrictValidationFailed', {
      my $ev = Spectacle.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'carries the attribute name on the exception', {
      my $ev = Spectacle.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.attribute).to.eq('name');
    }

    it 'carries the underlying message text', {
      my $ev = Spectacle.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.message-text).to.eq('must be present');
    }
  }

  context 'with a custom message', {
    it 'still raises X::StrictValidationFailed', {
      my $ev2 = Gala.build({name => 'A', score => 1});
      my $caught;
      try { $ev2.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'preserves the custom message', {
      my $ev2 = Gala.build({name => 'A', score => 1});
      my $caught;
      try { $ev2.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.message-text).to.eq('is too low');
    }
  }
}
