
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Message;
use ORM::ActiveRecord::Validations::Validator;
use ORM::ActiveRecord::Support::Utils;

class Validators is export {
  has @.validators       of Validator;
  has @.each-validators  of EachValidator;
  has @.with-validators  of WithValidator;
  has @.associated       of AssociatedValidator;

  method validate(DB $db, Mu:D $obj) {
    for @!validators -> $validator {
      next unless $obj.^name eq $validator.klass.raku;
      my $field = $validator.field;
      my $ons = {};
      my $if = -> { True };
      my $unless = -> { False };
      my $exclusion = {};
      my $inclusion = {};
      my $format = {};
      my $msg = '';

      for $validator.params -> $param {
        given $param.keys.first {
          when 'on' { $ons = $param<on> }
          when /if/ { $if = $param{"if\tTrue"} }
          when /unless/ { $unless = $param{"unless\tTrue"} }
          when 'message' { $msg = $param<message> }
          when 'exclusion' { $exclusion = $param<exclusion> }
          when 'inclusion' { $inclusion = $param<inclusion> }
          when 'format' { $format = $param<format> }
        }
      }

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg) }
          when 'length' { self.validate-length(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg) }
          when 'acceptance' { self.validate-acceptance(:$obj, :$field, :$ons, :$if, :$unless, :$msg) }
          when 'confirmation' { self.validate-confirmation(:$obj, :$field, :$ons, :$if, :$unless, :$msg) }
          when 'exclusion' { self.validate-exclusion(:$obj, :$field, :$ons, :$if, :$unless, :$exclusion, :$msg) }
          when 'inclusion' { self.validate-inclusion(:$obj, :$field, :$ons, :$if, :$unless, :$inclusion, :$msg) }
          when 'format' { self.validate-format(:$obj, :$field, :$ons, :$if, :$unless, :$format, :$msg) }
          when 'numericality' { self.validate-numericality(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg) }
          when 'comparison' { self.validate-comparison(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg) }
          when 'uniqueness' { self.validate-uniqueness(:$db, :$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg) }
          when /on|message|if|unless/ {}
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }

    for @!each-validators -> $ev {
      next unless $obj.^name eq $ev.klass.raku;
      my $if = -> { True };
      my $unless = -> { False };
      for $ev.params.pairs -> $param {
        given $param.keys.first {
          when /if/ { $if = $param{"if\tTrue"} }
          when /unless/ { $unless = $param{"unless\tTrue"} }
        }
      }
      next unless $if() && !$unless();
      for $ev.fields -> $name {
        my $value = $obj."$name"();
        $ev.block.($obj, $name, $value);
      }
    }

    for @!with-validators -> $wv {
      next unless $obj.^name eq $wv.klass.raku;
      my $v = $wv.validator;
      my $instance = $v.DEFINITE ?? $v !! $v.new(|%($wv.options // {}));
      $instance.validate($obj);
    }

    for @!associated -> $av {
      next unless $obj.^name eq $av.klass.raku;
      self.validate-associated(:$obj, :name($av.name), :params($av.params));
    }
  }

  method validate-uniqueness(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg) {
    my ($, $scope) = $param.kv;

    if $scope ~~ Bool {
      self.validate-unique(:$db, :$obj, :$field, :$ons, :$if, :$unless, :$msg);
    } else {
      self.validate-unique-scope(:$db, :$obj, :$field, :$scope, :$ons, :$if, :$unless, :$msg);
    }
  }

  method validate-unique(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my %where = $field.name => $obj."$field.name()"();
    my %record = $db.get-record(:@fields, :$table, :%where);

    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $value = '';
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-unique-scope(DB :$db, Mu:D :$obj, Field:D :$field, Pair:D :$scope, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my @fields = @$field;
    my $table = Utils.table-name($obj);
    my $keys = ($field.name, slip($scope.value.keys));
    my %where = $keys.map({ $_ => $obj."$_"() });
    my %record = $db.get-record(:@fields, :$table, :%where);
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && %record{$field.name} ~~ $obj."$field.name()"() {
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-presence(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && !$obj."$field.name()"() {
      my $template = $msg || 'must be present';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-length(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $max = $param<length><max>;
    my $min = $param<length><min>;
    my $is = $param<length><is>;
    my $in = $param<length><in>;

    my $str = $obj."$field.name()"();
    my $chars = $str ?? $str.chars !! 0;

    if $if() && !$unless() && $validate-on && $max && $chars > $max {
      my $value = "$max";
      my $template = $msg || 'only {value} characters allowed';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $min && $chars < $min {
      my $value = "$min";
      my $template = $msg || 'at least {value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $is && $chars != $is {
      my $value = "$is";
      my $template = $msg || 'exactly {value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $in && $chars !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $template = $msg || '{value} characters required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-acceptance(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    unless $if() && !$unless() && $validate-on && $obj."$field.name()"() {
      my $template = $msg || 'must be accepted';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-confirmation(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."{$field.name()}_confirmation"() ~~ Empty || $obj."{$field.name()}_confirmation"() !~~ $obj."$field.name()"() {
      my $template = $msg || 'must be confirmed';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-exclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$exclusion, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && !$obj."$field.name()"() || $obj."$field.name()"() (elem) $exclusion<in> {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-inclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$inclusion, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."$field.name()"() ~~ Empty || (not $obj."$field.name()"() (elem) $inclusion<in>) {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-format(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$format, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."$field.name()"() !~~ $format<with> {
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-numericality(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $gt = $param<numericality><gt>;
    my $gte = $param<numericality><gte>;
    my $lt = $param<numericality><lt>;
    my $lte = $param<numericality><lte>;
    my $in = $param<numericality><in>;

    my $number = $obj."$field.name()"().Int;

    if $if() && !$unless() && $validate-on && $gt && $number <= $gt {
      my $value = "$gt";
      my $template = $msg || 'more than {value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $gte && $number < $gte {
      my $value = "$gte";
      my $template = $msg || '{value} or more required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $lt && $number >= $lt {
      my $value = "$lt";
      my $template = $msg || 'less than {value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $lte && $number > $lte {
      my $value = "$lte";
      my $template = $msg || '{value} or less required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }

    if $if() && !$unless() && $validate-on && $in && $number !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $template = $msg || '{value} required';
      my $message = Message.build(:$template, :$obj, :$field, :$value);
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-comparison(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg) {
    my $validate-on = self.validate-on(:$obj, :$ons);
    return unless $if() && !$unless() && $validate-on;

    my $opts = $param<comparison>;
    my $actual = $obj."$field.name()"();
    return unless $actual.defined;

    my sub resolve($v) {
      return Nil unless $v.defined;
      if $v ~~ Str && $obj.has-attribute($v) {
        return $obj."$v"();
      }
      $v;
    }

    my sub cmp-ok($a, $b, $op) {
      given $op {
        when 'gt'  { return $a cmp $b == More }
        when 'gte' { return ($a cmp $b) == More || ($a cmp $b) == Same }
        when 'lt'  { return $a cmp $b == Less }
        when 'lte' { return ($a cmp $b) == Less || ($a cmp $b) == Same }
        when 'eq'  { return $a cmp $b == Same }
        when 'ne'  { return $a cmp $b != Same }
      }
      False;
    }

    my %templates = %(
      gt  => 'must be greater than {value}',
      gte => 'must be greater than or equal to {value}',
      lt  => 'must be less than {value}',
      lte => 'must be less than or equal to {value}',
      eq  => 'must be equal to {value}',
      ne  => 'must be other than {value}',
    );

    for <gt gte lt lte eq ne> -> $op {
      next unless $opts{$op}:exists;
      my $resolved = resolve($opts{$op});
      next unless $resolved.defined;
      next if cmp-ok($actual, $resolved, $op);
      my $label = $opts{$op} ~~ Str && $obj.has-attribute($opts{$op})
        ?? $opts{$op}
        !! "$resolved";
      my $template = $msg || %templates{$op};
      my $message = Message.build(:$template, :$obj, :$field, :value($label));
      my $e = Error.new(:$field, :$message);
      $obj.errors.push($e);
    }
  }

  method validate-associated(Mu:D :$obj, Str:D :$name, Hash:D :$params) {
    my $if = -> { True };
    my $unless = -> { False };
    my $msg = '';
    my $ons = {};
    for $params.pairs -> $param {
      given $param.keys.first {
        when 'on' { $ons = $param<on> }
        when /if/ { $if = $param{"if\tTrue"} }
        when /unless/ { $unless = $param{"unless\tTrue"} }
        when 'message' { $msg = $param<message> }
      }
    }
    my $validate-on = self.validate-on(:$obj, :$ons);
    return unless $if() && !$unless() && $validate-on;

    my @targets;
    my $is-many   = ($obj.has-manys{$name}:exists);
    my $is-habtm  = ($obj.habtms{$name}:exists);
    my $is-one    = ($obj.has-ones{$name}:exists);
    my $is-bt     = ($obj.belongs-tos{$name}:exists);
    if $is-many || $is-habtm {
      @targets = $obj."$name"().list;
    } elsif $is-one {
      my $r = $obj."$name"();
      @targets = ($r,) if $r.defined;
    } elsif $is-bt {
      my $r = $obj.attrs{$name} // $obj."$name"();
      @targets = ($r,) if $r.defined;
    } else {
      return;
    }

    my $bad = False;
    for @targets -> $r {
      next unless $r.defined;
      $bad = True unless $r.is-valid;
    }

    if $bad {
      my $field = $obj.get-field($name) // Field.new(:$name, :type('association'));
      my $template = $msg || 'is invalid';
      my $message = Message.build(:$template, :$obj, :$field);
      $obj.errors.push(Error.new(:$field, :$message));
    }
  }

  method validate-on(Mu:D :$obj, Hash:D :$ons) {
    my $on-create = $ons<create>;
    my $on-update = $ons<update>;

    ($on-create && $obj.id == 0) || ($on-update && $obj.id != 0) || (!$on-create && !$on-update);
  }
}
