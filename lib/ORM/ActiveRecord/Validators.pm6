
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Validator;
use ORM::ActiveRecord::Utils;

class Validators is export {
  has @.validators of Validator;

  method validate(DB $db, Mu:D $obj) {
    for @!validators {
      next unless $obj.^name eq .klass.perl;
      my $field = .field;
      my $ons = {};

      for .params -> $param {
        given $param.keys.first {
          when 'on' { $ons = $param<on> }
        }
      }

      for .params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence($obj, $field, $ons, $param) }
          when 'length' { self.validate-length($obj, $field, $ons, $param) }
          when 'acceptance' { self.validate-acceptance($obj, $field, $ons) }
          when 'confirmation' { self.validate-confirmation($obj, $field, $ons) }
          when 'exclusion' { self.validate-exclusion($obj, $field, $ons, $param<exclusion>) }
          when 'inclusion' { self.validate-inclusion($obj, $field, $ons, $param<inclusion>) }
          when 'format' { self.validate-format($obj, $field, $ons, $param<format>) }
          when 'numericality' { self.validate-numericality($obj, $field, $ons, $param) }
          when 'uniqueness' { self.validate-uniqueness($db, $obj, $field, $ons) }
          when 'on' {}
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }
  }

  method validate-on(Mu:D $obj, Hash:D $ons) {
    my $on-create = $ons<create>;
    my $on-update = $ons<update>;

    ($on-create && $obj.id == 0) || ($on-update && $obj.id != 0) || (!$on-create && !$on-update);
  }

  method validate-presence(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && !$obj."$field.name()"() {
      my $e = Error.new(:$field, :message('must be present'));
      $obj.errors.push($e);
    }
  }

  method validate-length(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params) {
    my $validate-on = self.validate-on($obj, $ons);

    my $max = $params<length><max>;
    my $min = $params<length><min>;
    my $is = $params<length><is>;
    my $in = $params<length><in>;

    my $str = $obj."$field.name()"();
    my $chars = $str ?? $str.chars !! 0;

    if $validate-on && $max && $chars > $max {
      my $e = Error.new(:$field, :message("only $max characters allowed"));
      $obj.errors.push($e);
    }

    if $validate-on && $min && $chars < $min {
      my $e = Error.new(:$field, :message("at least $min characters required"));
      $obj.errors.push($e);
    }

    if $validate-on && $is && $chars != $is {
      my $e = Error.new(:$field, :message("exactly $is characters required"));
      $obj.errors.push($e);
    }

    if $validate-on && $in && $chars !~~ $in {
      my $e = Error.new(:$field, :message("{$in.min} to {$in.max} characters required"));
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D $obj, Field:D $field, Hash:D $ons) {
    my $validate-on = self.validate-on($obj, $ons);

    unless $validate-on && $obj."$field.name()"() {
      my $e = Error.new(:$field, :message('must be accepted'));
      $obj.errors.push($e);
    }
  }

  method validate-confirmation(Mu:D $obj, Field:D $field, Hash:D $ons) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."{$field.name()}_confirmation"() ~~ Empty || $obj."{$field.name()}_confirmation"() !~~ $obj."$field.name()"() {
      my $e = Error.new(:$field, :message('must be confirmed'));
      $obj.errors.push($e);
    }
  }

  method validate-exclusion(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $exclusion) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && !$obj."$field.name()"() || $obj."$field.name()"() (elem) $exclusion<in> {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-inclusion(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $inclusion) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."$field.name()"() ~~ Empty || (not $obj."$field.name()"() (elem) $inclusion<in>) {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-format(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $format) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."$field.name()"() !~~ $format<with> {
      my $e = Error.new(:$field, :message('is invalid'));
      $obj.errors.push($e);
    }
  }

  method validate-numericality(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params) {
    my $validate-on = self.validate-on($obj, $ons);

    my $gt = $params<numericality><gt>;
    my $gte = $params<numericality><gte>;
    my $lt = $params<numericality><lt>;
    my $lte = $params<numericality><lte>;
    my $in = $params<numericality><in>;

    my $number = $obj."$field.name()"().Int;

    if $validate-on && $gt && $number <= $gt {
      my $e = Error.new(:$field, :message("more than $gt required"));
      $obj.errors.push($e);
    }

    if $validate-on && $gte && $number < $gte {
      my $e = Error.new(:$field, :message("$gte or more required"));
      $obj.errors.push($e);
    }

    if $validate-on && $lt && $number >= $lt {
      my $e = Error.new(:$field, :message("less than $lt required"));
      $obj.errors.push($e);
    }

    if $validate-on && $lte && $number > $lte {
      my $e = Error.new(:$field, :message("$lte or less required"));
      $obj.errors.push($e);
    }

    if $validate-on && $in && $number !~~ $in {
      my $e = Error.new(:$field, :message("{$in.min} to {$in.max} required"));
      $obj.errors.push($e);
    }
  }

  method validate-uniqueness(DB $db, Mu:D $obj, Field:D $field, Hash:D $ons) {
    return if $obj.id;

    if $obj."$field.name()"() !~~ Empty {
      my @fields = @$field;
      my $table = Utils.table-name($obj);
      my %where = $field.name => $obj."$field.name()"();
      my %record = $db.get-record(:@fields, :$table, :%where);

      my $validate-on = self.validate-on($obj, $ons);

      if $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
        my $e = Error.new(:$field, :message('must be unique'));
        $obj.errors.push($e);
      }
    }
  }
}
