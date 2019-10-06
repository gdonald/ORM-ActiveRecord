
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Validator;
use ORM::ActiveRecord::Utils;

class Validators is export {
  has @.validators of Validator;

  method validate(DB $db, Mu:D $obj) {
    for @!validators -> $validator {
      next unless $obj.^name eq $validator.klass.perl;
      my $field = $validator.field;
      my $ons = {};
      my $msg = '';

      for $validator.params -> $param {
        given $param.keys.first {
          when 'on' { $ons = $param<on> }
          when 'message' { $msg = $param<message> }
        }
      }

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence($obj, $field, $ons, $param, $msg) }
          when 'length' { self.validate-length($obj, $field, $ons, $param, $msg) }
          when 'acceptance' { self.validate-acceptance($obj, $field, $ons, $msg) }
          when 'confirmation' { self.validate-confirmation($obj, $field, $ons, $msg) }
          when 'exclusion' { self.validate-exclusion($obj, $field, $ons, $param<exclusion>, $msg) }
          when 'inclusion' { self.validate-inclusion($obj, $field, $ons, $param<inclusion>, $msg) }
          when 'format' { self.validate-format($obj, $field, $ons, $param<format>, $msg) }
          when 'numericality' { self.validate-numericality($obj, $field, $ons, $param, $msg) }
          when 'uniqueness' { self.validate-uniqueness($db, $obj, $field, $ons, $param, $msg) }
          when /on|message/ {}
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }
  }

  method validate-uniqueness(DB $db, Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $param, Str:D $msg) {
    my ($, $scope) = $param.kv;

    if $scope ~~ Bool {
      self.validate-unique($db, $obj, $field, $ons, $msg);
    } else {
      self.validate-unique-scope($db, $obj, $field, $scope, $ons, $msg);
    }
  }

  method validate-unique(DB $db, Mu:D $obj, Field:D $field, Hash:D $ons, Str:D $msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my %where = $field.name => $obj."$field.name()"();
    my %record = $db.get-record(:@fields, :$table, :%where);

    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $message = $msg || 'must be unique';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-unique-scope(DB $db, Mu:D $obj, Field:D $field, Pair:D $scope, Hash:D $ons, Str:D $msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my $keys = ($field.name, slip($scope.value.keys));
    my %where = $keys.map({ $_ => $obj."$_"() });
    my %record = $db.get-record(:@fields, :$table, :%where);
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $message = $msg || 'must be unique';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-presence(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && !$obj."$field.name()"() {
      my $message = $msg || 'must be present';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-length(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    my $max = $params<length><max>;
    my $min = $params<length><min>;
    my $is = $params<length><is>;
    my $in = $params<length><in>;

    my $str = $obj."$field.name()"();
    my $chars = $str ?? $str.chars !! 0;

    if $validate-on && $max && $chars > $max {
      my $message = $msg || "only $max characters allowed";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $min && $chars < $min {
      my $message = $msg || "at least $min characters required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $is && $chars != $is {
      my $message = $msg || "exactly $is characters required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $in && $chars !~~ $in {
      my $message = $msg || "{$in.min} to {$in.max} characters required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D $obj, Field:D $field, Hash:D $ons, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    unless $validate-on && $obj."$field.name()"() {
      my $message = $msg || 'must be accepted';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-confirmation(Mu:D $obj, Field:D $field, Hash:D $ons, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."{$field.name()}_confirmation"() ~~ Empty || $obj."{$field.name()}_confirmation"() !~~ $obj."$field.name()"() {
      my $message = $msg || 'must be confirmed';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-exclusion(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $exclusion, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && !$obj."$field.name()"() || $obj."$field.name()"() (elem) $exclusion<in> {
      my $message = $msg || 'is invalid';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-inclusion(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $inclusion, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."$field.name()"() ~~ Empty || (not $obj."$field.name()"() (elem) $inclusion<in>) {
      my $message = $msg || 'is invalid';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-format(Mu:D $obj, Field:D $field, Hash:D $ons, Hash:D $format, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    if $validate-on && $obj."$field.name()"() !~~ $format<with> {
      my $message = $msg || 'is invalid';
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-numericality(Mu:D $obj, Field:D $field, Hash:D $ons, Pair:D $params, Str:D $msg) {
    my $validate-on = self.validate-on($obj, $ons);

    my $gt = $params<numericality><gt>;
    my $gte = $params<numericality><gte>;
    my $lt = $params<numericality><lt>;
    my $lte = $params<numericality><lte>;
    my $in = $params<numericality><in>;

    my $number = $obj."$field.name()"().Int;

    if $validate-on && $gt && $number <= $gt {
      my $message = $msg || "more than $gt required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $gte && $number < $gte {
      my $message = $msg || "$gte or more required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $lt && $number >= $lt {
      my $message = $msg || "less than $lt required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $lte && $number > $lte {
      my $message = $msg || "$lte or less required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $in && $number !~~ $in {
      my $message = $msg || "{$in.min} to {$in.max} required";
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-on(Mu:D $obj, Hash:D $ons) {
    my $on-create = $ons<create>;
    my $on-update = $ons<update>;

    ($on-create && $obj.id == 0) || ($on-update && $obj.id != 0) || (!$on-create && !$on-update);
  }
}
