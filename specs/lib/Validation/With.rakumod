use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

unit module Validation::With;

class NotEvilValidator is export {
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

class ScoreInsanityValidator is export {
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

class Cabaret is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-with(NotEvilValidator.new);
    self.validates-with(ScoreInsanityValidator, :cap(50));
  }
}

GLOBAL::<Cabaret> := Cabaret;
GLOBAL::<NotEvilValidator> := NotEvilValidator;
GLOBAL::<ScoreInsanityValidator> := ScoreInsanityValidator;
