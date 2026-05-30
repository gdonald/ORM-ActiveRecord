use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::As;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'as: option overrides {attribute} in messages', {
  before-each { Premiere.destroy-all }
  after-each  { Premiere.destroy-all }

  context 'presence with as: alias', {
    it 'is invalid when max_score is missing', {
      my $ev = Premiere.build({name => 'A', score => 5, max_score => 0});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'uses the as: label in the message template', {
      my $ev = Premiere.build({name => 'A', score => 5, max_score => 0});
      $ev.is-invalid;
      expect($ev.errors.max_score[0]).to.eq('Maximum Score must be present');
    }
  }

  context 'numericality with as: alias', {
    it 'is invalid when below gte threshold', {
      my $ev = Encore.build({name => 'A', score => 1, max_score => 1});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'uses the as: label in the numericality message', {
      my $ev = Encore.build({name => 'A', score => 1, max_score => 1});
      $ev.is-invalid;
      expect($ev.errors.score[0]).to.eq('Player Score must be at least 10');
    }
  }

  context 'when valid', {
    it 'has no error', {
      my $ev = Premiere.build({name => 'A', score => 5, max_score => 99});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'has no max_score error on the errors object', {
      my $ev = Premiere.build({name => 'A', score => 5, max_score => 99});
      $ev.is-valid;
      expect($ev.errors.max_score).to.be-falsy;
    }
  }
}
