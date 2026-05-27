use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CtxPhevent is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :step_one } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

class CtxPhevent2 is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',      { :presence }
    self.validate: 'score',     { :presence, on => { :create } }
    self.validate: 'max_score', { :presence, on => { :step_two } }
  }
}

describe 'validation context (on:)', {
  before-each { CtxPhevent.destroy-all }
  after-each  { CtxPhevent.destroy-all }

  context 'default context with no validators triggered', {
    it 'skips step_one and step_two validators', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      expect($e.is-valid).to.be-truthy;
    }
  }

  context 'explicit step_one context', {
    it 'fires presence(score)', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      expect($e.is-invalid(:context<step_one>)).to.be-truthy;
    }

    it 'reports the score error', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.is-invalid(:context<step_one>);
      expect($e.errors.score[0]).to.eq('must be present');
    }

    it 'does not run step_two validators', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.is-invalid(:context<step_one>);
      expect($e.errors.max_score).to.be-falsy;
    }
  }

  context 'explicit step_two context', {
    it 'fires presence(max_score)', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      expect($e.is-invalid(:context<step_two>)).to.be-truthy;
    }

    it 'reports the max_score error', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.is-invalid(:context<step_two>);
      expect($e.errors.max_score[0]).to.eq('must be present');
    }

    it 'clears errors between is-invalid calls', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.is-invalid(:context<step_one>);
      $e.is-invalid(:context<step_two>);
      expect($e.errors.score).to.be-falsy;
    }
  }

  context 'no-context validators always fire', {
    it 'is invalid under step_one when name is blank', {
      my $e = CtxPhevent.build({name => '', score => 5, max_score => 5});
      expect($e.is-invalid(:context<step_one>)).to.be-truthy;
    }

    it 'reports the name presence error', {
      my $e = CtxPhevent.build({name => '', score => 5, max_score => 5});
      $e.is-invalid(:context<step_one>);
      expect($e.errors.name[0]).to.eq('must be present');
    }
  }

  context 'sticky validation-context setter', {
    it 'drives bare is-invalid', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.validation-context = 'step_one';
      expect($e.is-invalid).to.be-truthy;
    }

    it 'fires step_one validators under sticky context', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.validation-context = 'step_one';
      $e.is-invalid;
      expect($e.errors.score[0]).to.eq('must be present');
    }

    it 'clearing sticky context restores default behavior', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.validation-context = 'step_one';
      $e.is-invalid;
      $e.validation-context = Str;
      expect($e.is-valid).to.be-truthy;
    }
  }

  context 'explicit :context overrides sticky setter', {
    it 'fires step_two when sticky is step_one', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.validation-context = 'step_one';
      expect($e.is-invalid(:context<step_two>)).to.be-truthy;
    }

    it 'picks step_two validators', {
      my $e = CtxPhevent.build({name => 'A', score => 0, max_score => 0});
      $e.validation-context = 'step_one';
      $e.is-invalid(:context<step_two>);
      expect($e.errors.max_score[0]).to.eq('must be present');
    }
  }

  context ':create context derived for new records', {
    it 'fires the on::create validator when no context is given', {
      my $e = CtxPhevent2.build({name => 'A', max_score => 5});
      expect($e.is-invalid).to.be-truthy;
    }
  }
}
