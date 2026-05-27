use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class AnbPhevent is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'score', { :presence, numericality => { gt => 0 }, allow-nil => True }
  }
}

class AnbPhevent2 is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { :presence, length => { min => 3 }, allow-blank => True }
  }
}

class AnbPhevent3 is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name', { length => { min => 3 }, allow_blank => True }
  }
}

describe 'allow-nil and allow-blank options', {
  before-each { AnbPhevent.destroy-all }
  after-each  { AnbPhevent.destroy-all }

  context 'allow-nil with presence + numericality', {
    it 'passes when score is above zero', {
      my $ev = AnbPhevent.build({name => 'A', score => 5});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'still fails when value is defined but invalid', {
      my $ev = AnbPhevent.build({name => 'A', score => 0});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'skips presence + numericality when nil', {
      my $ev = AnbPhevent.build({name => 'A'});
      $ev.write-attribute('score', Nil);
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'allow-blank with presence + length', {
    it 'still fails non-blank short value', {
      my $ev = AnbPhevent2.build({name => 'AB'});
      expect($ev.is-invalid).to.be-truthy;
    }

    it 'reports length error for non-blank short value', {
      my $ev = AnbPhevent2.build({name => 'AB'});
      $ev.is-invalid;
      expect($ev.errors.name[0]).to.eq('at least 3 characters required');
    }

    it 'skips all validators when value is blank', {
      my $ev = AnbPhevent2.build({name => ''});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'treats whitespace-only as blank', {
      my $ev = AnbPhevent2.build({name => '   '});
      expect($ev.is-valid).to.be-truthy;
    }
  }

  context 'snake_case allow_blank', {
    it 'passes when blank', {
      my $ev = AnbPhevent3.build({name => ''});
      expect($ev.is-valid).to.be-truthy;
    }

    it 'still fails non-blank short value', {
      my $ev = AnbPhevent3.build({name => 'XY'});
      expect($ev.is-invalid).to.be-truthy;
    }
  }
}
