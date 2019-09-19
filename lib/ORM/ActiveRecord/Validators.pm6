
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
          when 'length' { self.validate-length($obj, $field, $param) }
          when 'acceptance' { self.validate-acceptance($obj, $field) }
          when 'confirmation' { self.validate-confirmation($obj, $field) }
          when 'exclusion' { self.validate-exclusion($obj, $field, $param<exclusion>) }
          when 'inclusion' { self.validate-inclusion($obj, $field, $param<inclusion>) }
          when 'format' { self.validate-format($obj, $field, $param<format>) }
          when 'numericality' { self.validate-numericality($obj, $field, $param) }
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

  method validate-length(Mu:D $obj, Str:D $field, Pair:D $params) {
    my $max = $params<length><max>;
    my $min = $params<length><min>;
    my $is = $params<length><is>;
    my $in = $params<length><in>;

    if $max && $obj."$field"().chars > $max {
      my $e = Error.new(:$field, :message("only $max characters allowed"));
      $obj.errors.push($e);
    }

    if $min && $obj."$field"().chars < $min {
      my $e = Error.new(:$field, :message("at least $min characters required"));
      $obj.errors.push($e);
    }

    if $is && $obj."$field"().chars != $is {
      my $e = Error.new(:$field, :message("exactly $is characters required"));
      $obj.errors.push($e);
    }

    if $in && $obj."$field"().chars !~~ $in {
      my $e = Error.new(:$field, :message("{$in.min} to {$in.max} characters required"));
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D $obj, Str:D $field) {
    unless $obj."$field"() {
      my $e = Error.new(:$field, :message('must be accepted'));
      $obj.errors.push($e);
    }
  }

  method validate-confirmation(Mu:D $obj, Str:D $field) {
    if $obj."{$field}_confirmation"() ~~ Empty || $obj."{$field}_confirmation"() !~~ $obj."$field"() {
      my $e = Error.new(:$field, :message('must be confirmed'));
      $obj.errors.push($e);
    }
  }

  method validate-exclusion(Mu:D $obj, Str:D $field, Hash:D $exclusion) {
    if $obj."$field"() ~~ Empty || $obj."$field"() (elem) $exclusion<in> {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-inclusion(Mu:D $obj, Str:D $field, Hash:D $inclusion) {
    if $obj."$field"() ~~ Empty || (not $obj."$field"() (elem) $inclusion<in>) {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-format(Mu:D $obj, Str:D $field, Hash:D $format) {
    if $obj."$field"() !~~ $format<with> {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-numericality(Mu:D $obj, Str:D $field, Pair:D $params) {
    my $gt = $params<numericality><gt>;
    my $gte = $params<numericality><gte>;
    my $lt = $params<numericality><lt>;
    my $lte = $params<numericality><lte>;
    my $in = $params<numericality><in>;

    if $gt && $obj."$field"().Int <= $gt {
      my $e = Error.new(:$field, :message("more than $gt required"));
      $obj.errors.push($e);
    }

    if $gte && $obj."$field"().Int < $gte {
      my $e = Error.new(:$field, :message("$gte or more required"));
      $obj.errors.push($e);
    }

    if $lt && $obj."$field"().Int >= $lt {
      my $e = Error.new(:$field, :message("less than $lt required"));
      $obj.errors.push($e);
    }

    if $lte && $obj."$field"().Int > $lte {
      my $e = Error.new(:$field, :message("$lte or less required"));
      $obj.errors.push($e);
    }

    if $in && $obj."$field"().Int !~~ $in {
      my $e = Error.new(:$field, :message("{$in.min} to {$in.max} required"));
      $obj.errors.push($e);
    }
  }
}
