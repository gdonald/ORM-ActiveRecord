use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class InImage is Model {
  method table-name { 'images' }

  submethod BUILD {
    self.validate: 'ext', { :presence, inclusion => { in => <gif jpeg jpg png> } }
  }
}

my @presence-or-invalid = ['must be present', 'is invalid'];

describe 'inclusion validator', {
  after-each { InImage.destroy-all }

  context 'missing ext', {
    it 'is invalid', {
      my $image = InImage.build({});
      expect($image.is-invalid).to.be-truthy;
    }

    it 'reports a presence or invalid error', {
      my $image = InImage.build({});
      $image.is-invalid;
      expect(@presence-or-invalid.grep($image.errors.ext[0]).elems).to.be-greater-than(0);
    }

    it 'reports a second presence or invalid error', {
      my $image = InImage.build({});
      $image.is-invalid;
      expect(@presence-or-invalid.grep($image.errors.ext[1]).elems).to.be-greater-than(0);
    }
  }

  context 'unknown ext', {
    it 'is invalid', {
      my $image = InImage.build({ext => 'foo'});
      expect($image.is-invalid).to.be-truthy;
    }

    it 'reports "is invalid"', {
      my $image = InImage.build({ext => 'foo'});
      $image.is-invalid;
      expect($image.errors.ext[0]).to.eq('is invalid');
    }
  }

  context 'allowed ext', {
    it 'is valid', {
      my $image = InImage.build({ext => 'jpg'});
      expect($image.is-valid).to.be-truthy;
    }

    it 'has no format error', {
      my $image = InImage.build({ext => 'jpg'});
      $image.is-valid;
      expect($image.errors.format).to.be-falsy;
    }
  }
}
