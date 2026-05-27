use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class Phevent is Model {
  submethod BUILD {
    self.validate: 'score', { comparison => { gt => 0 } }
    self.validate: 'max_score', { comparison => { gte => 'score' } }
  }
}

class PhCmp is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { lt => 100 } }
    self.validate: 'max_score', { comparison => { lte => 100 } }
  }
}

class PhEq is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { eq => 'max_score' } }
  }
}

class PhNe is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { comparison => { ne => 'max_score' } }
  }
}

describe 'comparison validator', {
  before-each { Phevent.destroy-all }
  after-each  { Phevent.destroy-all }

  context 'literal gt + attribute gte', {
    it 'passes when score>0 and max_score>=score', {
      my $ev = Phevent.build({name => 'A', score => 5, max_score => 10});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'fails when score is not greater than 0', {
      my $ev = Phevent.build({name => 'A', score => 0, max_score => 10});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'uses the literal value in the gt message', {
      my $ev = Phevent.build({name => 'A', score => 0, max_score => 10});
      $ev.is-invalid;
      expect($ev.errors.score[0]).to.eq('must be greater than 0');
    }

    it 'fails when max_score is not gte score', {
      my $ev = Phevent.build({name => 'A', score => 5, max_score => 3});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'names the other attribute in the gte message', {
      my $ev = Phevent.build({name => 'A', score => 5, max_score => 3});
      $ev.is-invalid;
      expect($ev.errors.max_score[0]).to.eq('must be greater than or equal to score');
    }
  }

  context 'lt / lte', {
    it 'fails when score is not less than 100', {
      my $c = PhCmp.build({name => 'A', score => 100, max_score => 50});
      expect($c.is-invalid).to.be-truthy;
    }

    it 'reports the lt literal message', {
      my $c = PhCmp.build({name => 'A', score => 100, max_score => 50});
      $c.is-invalid;
      expect($c.errors.score[0]).to.eq('must be less than 100');
    }

    it 'fails when max_score is greater than 100', {
      my $c = PhCmp.build({name => 'A', score => 50, max_score => 101});
      expect($c.is-invalid).to.be-truthy;
    }

    it 'reports the lte literal message', {
      my $c = PhCmp.build({name => 'A', score => 50, max_score => 101});
      $c.is-invalid;
      expect($c.errors.max_score[0]).to.eq('must be less than or equal to 100');
    }

    it 'passes at lt/lte boundaries', {
      my $c = PhCmp.build({name => 'A', score => 50, max_score => 75});
      expect($c.is-valid).to.be-truthy;
    }
  }

  context 'eq', {
    it 'passes when values are equal', {
      my $eq = PhEq.build({name => 'E', score => 5, max_score => 5});
      expect($eq.is-valid).to.be-truthy;
    }

    it 'fails when values differ', {
      my $eq = PhEq.build({name => 'E', score => 4, max_score => 5});
      expect($eq.is-invalid).to.be-truthy;
    }

    it 'names the other attribute in the eq message', {
      my $eq = PhEq.build({name => 'E', score => 4, max_score => 5});
      $eq.is-invalid;
      expect($eq.errors.score[0]).to.eq('must be equal to max_score');
    }
  }

  context 'ne', {
    it 'fails when values are equal', {
      my $ne = PhNe.build({name => 'N', score => 5, max_score => 5});
      expect($ne.is-invalid).to.be-truthy;
    }

    it 'names the other attribute in the ne message', {
      my $ne = PhNe.build({name => 'N', score => 5, max_score => 5});
      $ne.is-invalid;
      expect($ne.errors.score[0]).to.eq('must be other than max_score');
    }

    it 'passes when values differ', {
      my $ne = PhNe.build({name => 'N', score => 5, max_score => 6});
      expect($ne.is-valid).to.be-truthy;
    }
  }
}
