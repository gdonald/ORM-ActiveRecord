
use ORM::ActiveRecord::Error;

class Validator is export {
  my @.validators of Validator;

  has $.klass;
  has Str $.field;
  has Hash $.params;

  method validate($obj) {
    for Validator.validators -> $validator {
      next unless $obj.^name eq $validator.klass.perl;

      my $field = $validator.field;

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate_presence($obj, $field) }
          when 'length' { self.validate_length($obj, $field, $param<length>) }
        }
      }
    }
  }

  method validate_presence($obj, $field) {
    if $obj."$field"() ~~ Empty {
      my $e = Error.new(:$field, :message('must be present'));
      $obj.errors.push($e);
    }
  }

  method validate_length($obj, $field, $length) {
    my $max = $length<max>;
    my $min = $length<min>;

    if $max {
      if $obj."$field"().chars > $max {
        my $e = Error.new(:$field, :message("only $max characters allowed"));
        $obj.errors.push($e);
      }
    }

    if $min {
      if $obj."$field"().chars < $min {
        my $e = Error.new(:$field, :message("at least $min characters required"));
        $obj.errors.push($e);
      }
    }
  }
}
