use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::AllowNilBlank;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'allow-nil and allow-blank options', {
  before-each { Concert.destroy-all }
  after-each  { Concert.destroy-all }

  context 'allow-nil with presence + numericality', {
    it 'passes when score is above zero', {
      my $ev = Concert.build({name => 'A', score => 5});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'still fails when value is defined but invalid', {
      my $ev = Concert.build({name => 'A', score => 0});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'skips presence + numericality when nil', {
      my $ev = Concert.build({name => 'A'});
      $ev.write-attribute('score', Nil);
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'allow-blank with presence + length', {
    it 'still fails non-blank short value', {
      my $ev = Recital.build({name => 'AB'});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'reports length error for non-blank short value', {
      my $ev = Recital.build({name => 'AB'});
      $ev.is-invalid;
      expect($ev.errors.name[0]).to.eq('at least 3 characters required');
    }

    it 'skips all validators when value is blank', {
      my $ev = Recital.build({name => ''});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'treats whitespace-only as blank', {
      my $ev = Recital.build({name => '   '});
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'snake_case allow_blank', {
    it 'passes when blank', {
      my $ev = Festival.build({name => ''});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'still fails non-blank short value', {
      my $ev = Festival.build({name => 'XY'});
      expect($ev.is-invalid).to.be-truthy;
    }
  }
}
