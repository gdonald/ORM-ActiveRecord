use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Rerun;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'is-valid / is-invalid can be called repeatedly without leaking state', {
  before-each { RerunPhevent.destroy-all }
  after-each  { RerunPhevent.destroy-all }

  context 'first call on a broken record', {
    it 'reports invalid', {
      my $e = RerunPhevent.build({name => '', score => 5});
      expect($e.is-invalid).to.be-truthy;
    }

    it 'captures the presence error', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      expect($e.errors.name[0]).to.eq('must be present');
    }
  }

  context 'after fixing the attribute', {
    it 'becomes valid', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      $e.name = 'OK';
      expect($e.is-valid).to.be-truthy;
    }

    it 'clears the previous error', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      $e.name = 'OK';
      $e.is-valid;
      expect($e.errors.name).to.be-falsy;
    }
  }

  context 'after re-breaking the attribute', {
    it 'reports invalid again', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      $e.name = 'OK';
      $e.is-valid;
      $e.name = '';
      expect($e.is-invalid).to.be-truthy;
    }

    it 'reports a fresh error', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      $e.name = 'OK';
      $e.is-valid;
      $e.name = '';
      $e.is-invalid;
      expect($e.errors.name[0]).to.eq('must be present');
    }

    it 'does not accumulate duplicate errors', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid;
      $e.name = 'OK';
      $e.is-valid;
      $e.name = '';
      $e.is-invalid;
      expect($e.errors.errors.elems).to.eq(1);
    }
  }

  context 'five back-to-back is-invalid calls', {
    it 'still produces a single error', {
      my $e = RerunPhevent.build({name => '', score => 5});
      $e.is-invalid for ^5;
      expect($e.errors.errors.elems).to.eq(1);
    }
  }
}
