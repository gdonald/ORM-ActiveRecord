use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::Inclusion;

%*ENV<DISABLE-SQL-LOG> = True;

my @presence-or-invalid = ['must be present', 'is invalid'];

describe 'inclusion validator', {
  after-each { Image.destroy-all }

  context 'missing ext', {
    it 'is invalid', {
      my $image = Image.build({});
      expect($image.is-invalid).to.be-truthy;
    }

    it 'reports a presence or invalid error', {
      my $image = Image.build({});
      $image.is-invalid;
      expect(@presence-or-invalid.grep($image.errors.ext[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or invalid error', {
      my $image = Image.build({});
      $image.is-invalid;
      expect(@presence-or-invalid.grep($image.errors.ext[1]).elems).to.be-greater-than(0);
    }
  }

  context 'unknown ext', {
    it 'is invalid', {
      my $image = Image.build({ext => 'foo'});
      expect($image.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $image = Image.build({ext => 'foo'});
      $image.is-invalid;
      expect($image.errors.ext[0]).to.eq('is invalid');
    }
  }

  context 'allowed ext', {
    it 'is valid', {
      my $image = Image.build({ext => 'jpg'});
      expect($image.is-valid).to.be-truthy;
    }

    it 'has no format error', {
      my $image = Image.build({ext => 'jpg'});
      $image.is-valid;
      expect($image.errors.format).to.be-falsy;
    }
  }
}
