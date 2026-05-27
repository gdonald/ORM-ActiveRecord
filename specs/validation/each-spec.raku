use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

%*ENV<DISABLE-SQL-LOG> = True;

class PhEach is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <name>, -> $rec, $attr, $value {
      if $value && $value ~~ /^ <:Ll> / {
        my $f = Field.new(:name($attr), :type('string'));
        $rec.errors.push(Error.new(:field($f), :message('must start with capital letter')));
      }
    }
  }
}

class PhEachMulti is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <score max_score>, -> $rec, $attr, $value {
      if $value < 0 {
        my $f = Field.new(:name($attr), :type('integer'));
        $rec.errors.push(Error.new(:field($f), :message('must not be negative')));
      }
    }
  }
}

describe 'validates-each block validator', {
  before-each { PhEach.destroy-all }
  after-each  { PhEach.destroy-all }

  context 'single attribute', {
    it 'is invalid when name is lowercase', {
      my $e = PhEach.build({name => 'lowercase', score => 1, max_score => 1});
      expect($e.is-invalid).to.be-truthy;
    }

    it 'adds the block message', {
      my $e = PhEach.build({name => 'lowercase', score => 1, max_score => 1});
      $e.is-invalid;
      expect($e.errors.name[0]).to.eq('must start with capital letter');
    }

    it 'is valid when name starts with capital', {
      my $e = PhEach.build({name => 'Capital', score => 1, max_score => 1});
      expect($e.is-valid).to.be-truthy;
    }
  }

  context 'multiple attributes', {
    it 'is invalid when any score is negative', {
      my $m = PhEachMulti.build({name => 'A', score => -1, max_score => -2});
      expect($m.is-invalid).to.be-truthy;
    }

    it 'applies the block to score', {
      my $m = PhEachMulti.build({name => 'A', score => -1, max_score => -2});
      $m.is-invalid;
      expect($m.errors.score[0]).to.eq('must not be negative');
    }

    it 'applies the block to max_score', {
      my $m = PhEachMulti.build({name => 'A', score => -1, max_score => -2});
      $m.is-invalid;
      expect($m.errors.max_score[0]).to.eq('must not be negative');
    }

    it 'is valid when both scores are non-negative', {
      my $m = PhEachMulti.build({name => 'A', score => 1, max_score => 2});
      expect($m.is-valid).to.be-truthy;
    }
  }
}
