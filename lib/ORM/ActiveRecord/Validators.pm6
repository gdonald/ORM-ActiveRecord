
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Validator;

class Validators is export {
  has @.validators of Validator;

  method validate($obj) {
    for @!validators -> $validator {
      next unless $obj.^name eq $validator.klass.perl;
      my $field = $validator.field;

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence($obj, $field) }
          when 'length' { self.validate-length($obj, $field, $param<length>) }
        }
      }
    }
  }

  method validate-presence($obj, $field) {
    if $obj."$field"() ~~ Empty {
      my $e = Error.new(:$field, :message('must be present'));
      $obj.errors.push($e);
    }
  }

  method validate-length($obj, $field, $length) {
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
