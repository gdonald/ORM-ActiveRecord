use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

%*ENV<DISABLE-SQL-LOG> = True;

class NotEvilValidator {
  has Str $.banned = 'Evil';

  method validate($record) {
    if $record.attrs<name> eq $!banned {
      my $field = Field.new(:name('base'), :type('association'));
      $record.errors.push(
        Error.new(:$field, :message("'$!banned' is not allowed"))
      );
    }
  }
}

class ScoreInsanityValidator {
  has Int $.cap = 1000;

  method validate($record) {
    if $record.attrs<score> > $!cap {
      my $field = Field.new(:name('score'), :type('integer'));
      $record.errors.push(
        Error.new(:$field, :message("score exceeds cap of $!cap"))
      );
    }
  }
}

class PhWith is Model {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-with(NotEvilValidator.new);
    self.validates-with(ScoreInsanityValidator, :cap(50));
  }
}

describe 'validates-with', {
  before-each { PhWith.destroy-all }
  after-each  { PhWith.destroy-all }

  context 'banned name', {
    it 'is invalid', {
      my $w = PhWith.build({name => 'Evil', score => 5, max_score => 10});
      expect($w.is-invalid).to.be-truthy;
    }

    it 'runs the instance validator', {
      my $w = PhWith.build({name => 'Evil', score => 5, max_score => 10});
      $w.is-invalid;
      expect($w.errors.base[0]).to.eq("'Evil' is not allowed");
    }
  }

  context 'class + options validator', {
    it 'triggers when score exceeds cap', {
      my $w = PhWith.build({name => 'OK', score => 500, max_score => 1000});
      expect($w.is-invalid).to.be-truthy;
    }

    it 'forwards options to new()', {
      my $w = PhWith.build({name => 'OK', score => 500, max_score => 1000});
      $w.is-invalid;
      expect($w.errors.score[0]).to.eq('score exceeds cap of 50');
    }
  }

  context 'clean record', {
    it 'is valid', {
      my $w = PhWith.build({name => 'OK', score => 5, max_score => 10});
      expect($w.is-valid).to.be-truthy;
    }

    it 'has no base error', {
      my $w = PhWith.build({name => 'OK', score => 5, max_score => 10});
      $w.is-valid;
      expect($w.errors.base).to.be-falsy;
    }
  }
}
