use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::X;

%*ENV<DISABLE-SQL-LOG> = True;

class StPhevent is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { :presence, strict => True }
  }
}

class StPhevent2 is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { numericality => { gt => 5 }, :strict, message => 'is too low' }
  }
}

describe 'strict validation raises X::StrictValidationFailed', {
  before-each { StPhevent.destroy-all }
  after-each  { StPhevent.destroy-all }

  context 'when valid', {
    it 'does not raise', {
      my $ev = StPhevent.build({name => 'OK', score => 1});
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'when invalid', {
    it 'raises an exception', {
      my $ev = StPhevent.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.defined).to.be-truthy;
    }

    it 'raises X::StrictValidationFailed', {
      my $ev = StPhevent.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'carries the attribute name on the exception', {
      my $ev = StPhevent.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.attribute).to.eq('name');
    }

    it 'carries the underlying message text', {
      my $ev = StPhevent.build({name => '', score => 1});
      my $caught;
      try { $ev.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.message-text).to.eq('must be present');
    }
  }

  context 'with a custom message', {
    it 'still raises X::StrictValidationFailed', {
      my $ev2 = StPhevent2.build({name => 'A', score => 1});
      my $caught;
      try { $ev2.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught).to.be-a(X::StrictValidationFailed);
    }

    it 'preserves the custom message', {
      my $ev2 = StPhevent2.build({name => 'A', score => 1});
      my $caught;
      try { $ev2.is-valid; CATCH { default { $caught = $_ } } }
      expect($caught.message-text).to.eq('is too low');
    }
  }
}
