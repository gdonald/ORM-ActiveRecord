use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

unit module Validation::Each;

sub flag-name($rec, $attr, $value) is export {
  my $f = Field.new(:name($attr), :type('string'));
  $rec.errors.push(Error.new(:field($f), :message('name flagged')));
}

class PhEach is Model is export {
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

class PhEachMulti is Model is export {
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

class PhEachIf is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { :if => { self.score > 0 } };
  }
}

class PhEachUnless is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { :unless => { self.score > 0 } };
  }
}

class PhEachOn is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { on => { :review } };
  }
}

class PhEachStrict is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validates-each: <name>, -> $rec, $attr, $value {
      if $value && $value ~~ /^ <:Ll> / {
        my $f = Field.new(:name($attr), :type('string'));
        $rec.errors.push(Error.new(:field($f), :message('must start with capital letter')));
      }
    }, { :strict };
  }
}

GLOBAL::<PhEach>        := PhEach;
GLOBAL::<PhEachMulti>   := PhEachMulti;
GLOBAL::<PhEachIf>      := PhEachIf;
GLOBAL::<PhEachUnless>  := PhEachUnless;
GLOBAL::<PhEachOn>      := PhEachOn;
GLOBAL::<PhEachStrict>  := PhEachStrict;
