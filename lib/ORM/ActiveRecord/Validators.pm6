
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Error;
use ORM::ActiveRecord::Field;
use ORM::ActiveRecord::Message;
use ORM::ActiveRecord::Validator;
use ORM::ActiveRecord::Utils;

class Validators is export {
  has @.validators of Validator;

  method validate(DB $db, Mu:D $obj) {
    for @!validators -> $validator {
      next unless $obj.^name eq $validator.klass.perl;
      my $field = $validator.field;
      my $ons = {};
      my $exclusion = {};
      my $inclusion = {};
      my $format = {};
      my $msg = '';

      for $validator.params -> $param {
        given $param.keys.first {
          when 'on' { $ons = $param<on> }
          when 'message' { $msg = $param<message> }
          when 'exclusion' { $exclusion = $param<exclusion> }
          when 'inclusion' { $inclusion = $param<inclusion> }
          when 'format' { $format = $param<format> }
        }
      }

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence(:$obj, :$field, :$ons, :$param, :$msg) }
          when 'length' { self.validate-length(:$obj, :$field, :$ons, :$param, :$msg) }
          when 'acceptance' { self.validate-acceptance(:$obj, :$field, :$ons, :$msg) }
          when 'confirmation' { self.validate-confirmation(:$obj, :$field, :$ons, :$msg) }
          when 'exclusion' { self.validate-exclusion(:$obj, :$field, :$ons, :$exclusion, :$msg) }
          when 'inclusion' { self.validate-inclusion(:$obj, :$field, :$ons, :$inclusion, :$msg) }
          when 'format' { self.validate-format(:$obj, :$field, :$ons, :$format, :$msg) }
          when 'numericality' { self.validate-numericality(:$obj, :$field, :$ons, :$param, :$msg) }
          when 'uniqueness' { self.validate-uniqueness(:$db, :$obj, :$field, :$ons, :$param, :$msg) }
          when /on|message/ {}
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }
  }

  method validate-uniqueness(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Pair:D :$param, Str:D :$msg) {
    my ($, $scope) = $param.kv;

    if $scope ~~ Bool {
      self.validate-unique(:$db, :$obj, :$field, :$ons, :$msg);
    } else {
      self.validate-unique-scope(:$db, :$obj, :$field, :$scope, :$ons, :$msg);
    }
  }

  method validate-unique(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Str:D :$msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my %where = $field.name => $obj."$field.name()"();
    my %record = $db.get-record(:@fields, :$table, :%where);

    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $value = '';
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-unique-scope(DB :$db, Mu:D :$obj, Field:D :$field, Pair:D :$scope, Hash:D :$ons, Str:D :$msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my $keys = ($field.name, slip($scope.value.keys));
    my %where = $keys.map({ $_ => $obj."$_"() });
    my %record = $db.get-record(:@fields, :$table, :%where);
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-presence(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && !$obj."$field.name()"() {
      my $template = $msg || 'must be present';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-length(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $max = $param<length><max>;
    my $min = $param<length><min>;
    my $is = $param<length><is>;
    my $in = $param<length><in>;

    my $str = $obj."$field.name()"();
    my $chars = $str ?? $str.chars !! 0;

    if $validate-on && $max && $chars > $max {
      my $value = "$max";
      my $template = $msg || 'only {value} characters allowed';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $min && $chars < $min {
      my $value = "$min";
      my $template = $msg || 'at least {value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $is && $chars != $is {
      my $value = "$is";
      my $template = $msg || 'exactly {value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $in && $chars !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $template = $msg || '{value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    unless $validate-on && $obj."$field.name()"() {
      my $template = $msg || 'must be accepted';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-confirmation(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && $obj."{$field.name()}_confirmation"() ~~ Empty || $obj."{$field.name()}_confirmation"() !~~ $obj."$field.name()"() {
      my $template = $msg || 'must be confirmed';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-exclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Hash:D :$exclusion, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && !$obj."$field.name()"() || $obj."$field.name()"() (elem) $exclusion<in> {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-inclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Hash:D :$inclusion, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && $obj."$field.name()"() ~~ Empty || (not $obj."$field.name()"() (elem) $inclusion<in>) {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-format(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Hash:D :$format, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $validate-on && $obj."$field.name()"() !~~ $format<with> {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-numericality(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $gt = $param<numericality><gt>;
    my $gte = $param<numericality><gte>;
    my $lt = $param<numericality><lt>;
    my $lte = $param<numericality><lte>;
    my $in = $param<numericality><in>;

    my $number = $obj."$field.name()"().Int;

    if $validate-on && $gt && $number <= $gt {
      my $value = "$gt";
      my $template = $msg || 'more than {value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $gte && $number < $gte {
      my $value = "$gte";
      my $template = $msg || '{value} or more required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $lt && $number >= $lt {
      my $value = "$lt";
      my $template = $msg || 'less than {value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $lte && $number > $lte {
      my $value = "$lte";
      my $template = $msg || '{value} or less required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $validate-on && $in && $number !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $template = $msg || '{value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-on(Mu:D :$obj, Hash:D :$ons) {
    my $on-create = $ons<create>;
    my $on-update = $ons<update>;

    ($on-create && $obj.id == 0) || ($on-update && $obj.id != 0) || (!$on-create && !$on-update);
  }
}
