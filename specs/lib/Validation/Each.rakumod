use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

unit module Validation::Each;

sub flag-name($rec, $attr, $value) is export {
  my $f = Field.new(:name($attr), :type('string'));
  $rec.errors.push(Error.new(:field($f), :message('name flagged')));
}

class Symphony is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <name>, -> $rec, $attr, $value {
      if $value && $value ~~ /^ <:Ll> / {
        my $f = Field.new(:name($attr), :type('string'));
        $rec.errors.push(Error.new(:field($f), :message('must start with capital letter')));
      }
    }
  }
}

class Fanfare is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <score max_score>, -> $rec, $attr, $value {
      if $value < 0 {
        my $f = Field.new(:name($attr), :type('integer'));
        $rec.errors.push(Error.new(:field($f), :message('must not be negative')));
      }
    }
  }
}

class Overture is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { :if => { self.score > 0 } };
  }
}

class Interlude is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { :unless => { self.score > 0 } };
  }
}

class Prelude is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <name>, &flag-name, { on => { :review } };
  }
}

class Aria is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validates-each: <name>, -> $rec, $attr, $value {
      if $value && $value ~~ /^ <:Ll> / {
        my $f = Field.new(:name($attr), :type('string'));
        $rec.errors.push(Error.new(:field($f), :message('must start with capital letter')));
      }
    }, { :strict };
  }
}

GLOBAL::<Symphony>  := Symphony;
GLOBAL::<Fanfare>   := Fanfare;
GLOBAL::<Overture>  := Overture;
GLOBAL::<Interlude> := Interlude;
GLOBAL::<Prelude>   := Prelude;
GLOBAL::<Aria>      := Aria;
