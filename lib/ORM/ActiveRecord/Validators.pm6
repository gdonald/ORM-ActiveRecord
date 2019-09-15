
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Validator;

class Validators is export {
  has @.validators of Validator;

  method validate(Mu:D $obj) {
    for @!validators {
      next unless $obj.^name eq .klass.perl;
      my $field = .field;

      for .params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence($obj, $field) }
          when 'length' { self.validate-length($obj, $field, $param<length>) }
          when 'acceptance' { self.validate-acceptance($obj, $field) }
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }
  }

  method validate-presence(Mu:D $obj, Str:D $field) {
    if $obj."$field"() ~~ Empty {
      my $e = Error.new(:$field, :message('must be present'));
      $obj.errors.push($e);
    }
  }

  method validate-length(Mu:D $obj, Str:D $field, Hash:D $length) {
    my $max = $length<max>;
    my $min = $length<min>;

    if $max && $obj."$field"().chars > $max {
      my $e = Error.new(:$field, :message("only $max characters allowed"));
      $obj.errors.push($e);
    }

    if $min && $obj."$field"().chars < $min {
      my $e = Error.new(:$field, :message("at least $min characters required"));
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D $obj, Str:D $field) {
    unless $obj."$field"() {
      my $e = Error.new(:$field, :message('must be accepted'));
      $obj.errors.push($e);
    }
  }
}
