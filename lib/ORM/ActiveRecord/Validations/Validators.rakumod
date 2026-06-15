
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Message;
use ORM::ActiveRecord::Validations::Validator;
use ORM::ActiveRecord::Support::Utils;

class Validators is export {
  has @.validators       of Validator;
  has @.each-validators  of EachValidator;
  has @.with-validators  of WithValidator;
  has @.associated       of AssociatedValidator;
  has Str $.context is rw = '';

  method validate(DB $db, Mu:D $obj, Str :$context = '') {
    $!context = $context;
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
      my Bool $allow-nil   = False;
      my Bool $allow-blank = False;
      my Bool $strict      = False;
      my Str  $as          = '';

      for $validator.params -> $param {
        given $param.keys.first {
          when 'on' { $ons = $param<on> }
          when /if/ { $if = $param{"if\tTrue"} }
          when /unless/ { $unless = $param{"unless\tTrue"} }
          when 'message' { $msg = $param<message> }
          when 'exclusion' { $exclusion = $param<exclusion> }
          when 'inclusion' { $inclusion = $param<inclusion> }
          when 'format' { $format = $param<format> }
          when 'allow-nil' | 'allow_nil' { $allow-nil = so $param.value }
          when 'allow-blank' | 'allow_blank' { $allow-blank = so $param.value }
          when 'strict' { $strict = so $param.value }
          when 'as' { $as = ~$param.value }
        }
      }

      next if self.should-allow-skip(:$obj, :$field, :$allow-nil, :$allow-blank);

      for $validator.params -> $param {
        given $param.keys.first {
          when 'presence' { self.validate-presence(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg, :$strict, :$as) }
          when 'length' { self.validate-length(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg, :$strict, :$as) }
          when 'acceptance' { self.validate-acceptance(:$obj, :$field, :$ons, :$if, :$unless, :$msg, :$strict, :$as) }
          when 'confirmation' { self.validate-confirmation(:$obj, :$field, :$ons, :$if, :$unless, :$msg, :$strict, :$as) }
          when 'exclusion' { self.validate-exclusion(:$obj, :$field, :$ons, :$if, :$unless, :$exclusion, :$msg, :$strict, :$as) }
          when 'inclusion' { self.validate-inclusion(:$obj, :$field, :$ons, :$if, :$unless, :$inclusion, :$msg, :$strict, :$as) }
          when 'format' { self.validate-format(:$obj, :$field, :$ons, :$if, :$unless, :$format, :$msg, :$strict, :$as) }
          when 'numericality' { self.validate-numericality(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg, :$strict, :$as) }
          when 'comparison' { self.validate-comparison(:$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg, :$strict, :$as) }
          when 'uniqueness' { self.validate-uniqueness(:$db, :$obj, :$field, :$ons, :$if, :$unless, :$param, :$msg, :$strict, :$as) }
          when /on|message|if|unless|allow\-nil|allow_nil|allow\-blank|allow_blank|strict|as/ {}
          default { say 'unknown validation: ' ~ $param.keys.first; die }
        }
      }
    }

    for @!each-validators -> $ev {
      next unless $obj.^name eq $ev.klass.raku;

      my $if     = -> { True };
      my $unless = -> { False };
      my $ons    = {};
      my Bool $strict = False;

      for $ev.params.pairs -> $param {
        given $param.keys.first {
          when 'on'     { $ons = $param<on> }
          when 'strict' { $strict = so $param.value }
          when /if/     { $if = $param{"if\tTrue"} }
          when /unless/ { $unless = $param{"unless\tTrue"} }
        }
      }

      next unless $if() && !$unless();
      next unless self.validate-on(:$obj, :$ons);

      for $ev.fields -> $name {
        my $value = $obj."$name"();

        unless $strict {
          $ev.block.($obj, $name, $value);
          next;
        }

        my @snapshot = $obj.errors.objects;
        $ev.block.($obj, $name, $value);

        next unless $obj.errors.objects.elems > @snapshot.elems;

        my $added = $obj.errors.objects[@snapshot.elems];

        $obj.errors.clear;
        $obj.errors.push($_) for @snapshot;

        die X::StrictValidationFailed.new(
          :model($obj.^name),
          :attribute($added.attribute),
          :message-text($added.message),
        );
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

  method should-allow-skip(Mu:D :$obj, Field:D :$field, Bool:D :$allow-nil, Bool:D :$allow-blank --> Bool) {
    return False unless $allow-nil || $allow-blank;
    my $val;
    try { $val = $obj."{$field.name}"() }
    return True if $allow-nil && !$val.defined;

    if $allow-blank {
      return True unless $val.defined;
      given $val {
        when Str  { return True if $val eq '' || $val ~~ /^\s*$/ }
        when Bool { return True unless $val }
        when Positional { return True if $val.elems == 0 }
      }
    }

    False;
  }

  method record-error(Mu:D :$obj, Field:D :$field, Str:D :$message, Bool:D :$strict, Str :$type = 'invalid', :%options) {
    if $strict {
      die X::StrictValidationFailed.new(
        :model($obj.^name),
        :attribute($field.name),
        :message-text($message),
      );
    }

    $obj.errors.push(Error.new(:$field, :$message, :$type, :%options));
  }

  method validate-uniqueness(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $val = $param.value;
    my $scope-pair = Pair;
    my Bool $case-sensitive = True;
    my %conditions;

    given $val {
      when Bool {
      }
      when Pair {
        if $val.key eq 'scope' {
          $scope-pair = $val;
        }
      }
      when Hash | Map {
        if $val<scope>:exists {
          $scope-pair = (scope => $val<scope>);
        }
        if $val<case-sensitive>:exists {
          $case-sensitive = so $val<case-sensitive>;
        }
        elsif $val<case_sensitive>:exists {
          $case-sensitive = so $val<case_sensitive>;
        }
        if $val<conditions>:exists {
          %conditions = $val<conditions>.Hash;
        }
      }
    }

    if $scope-pair.defined {
      self.validate-unique-scope(:$db, :$obj, :$field, :scope($scope-pair), :$ons, :$if, :$unless, :$msg, :$strict, :$as, :$case-sensitive, :%conditions);
    } else {
      self.validate-unique(:$db, :$obj, :$field, :$ons, :$if, :$unless, :$msg, :$strict, :$as, :$case-sensitive, :%conditions);
    }
  }

  method validate-unique(DB :$db, Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg, Bool:D :$strict, Str:D :$as, Bool:D :$case-sensitive = True, :%conditions) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my $table = Utils.table-name($obj);
    my $col = $field.name;
    my $val = $obj."$col"();

    my $found = self.unique-lookup(:$db, :$table, :$col, :$val, :$case-sensitive, :%conditions);
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $found {
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<taken>);
    }
  }

  method validate-unique-scope(DB :$db, Mu:D :$obj, Field:D :$field, Pair:D :$scope, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg, Bool:D :$strict, Str:D :$as, Bool:D :$case-sensitive = True, :%conditions) {
    return if $obj.id || $obj."$field.name()"() ~~ Empty;

    my $table = Utils.table-name($obj);
    my $col = $field.name;
    my $val = $obj."$col"();

    my %scope-where;
    for $scope.value.keys -> $k {
      %scope-where{$k} = $obj."$k"();
    }
    for %conditions.kv -> $k, $v { %scope-where{$k} = $v }

    my $found = self.unique-lookup(:$db, :$table, :$col, :$val, :$case-sensitive, :conditions(%scope-where));
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $found {
      my $template = $msg || 'must be unique';
      my $message = Message.build(:$template, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<taken>);
    }
  }

  method unique-lookup(DB :$db, Str:D :$table, Str:D :$col, :$val, Bool:D :$case-sensitive, :%conditions --> Bool) {
    my @sql-parts;
    my @binds;

    if $val ~~ Str {
      @sql-parts.push: $db.case-eq-sql($col, :$case-sensitive);
      @binds.push: $val;
    } else {
      @sql-parts.push: "$col = ?";
      @binds.push: $val;
    }

    for %conditions.kv -> $k, $v {
      if $v.defined {
        @sql-parts.push: "$k = ?";
        @binds.push: $v;
      } else {
        @sql-parts.push: "$k IS NULL";
      }
    }

    my $where-clause = @sql-parts.join(' AND ');
    my $sql = "SELECT 1 FROM $table WHERE $where-clause LIMIT 1";
    my $stmt = $db.sanitize-sql-array([$sql, |@binds]);
    my @rows = $db.exec-stmt($stmt);

    @rows.elems.so;
  }

  method validate-presence(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && !$obj."$field.name()"() {
      my $message = Message.build(:override($msg), :default('must be present'), :type<blank>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<blank>);
    }
  }

  method validate-length(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $max = $param<length><max>;
    my $min = $param<length><min>;
    my $is = $param<length><is>;
    my $in = $param<length><in>;

    my $str = $obj."$field.name()"();
    my $chars = $str ?? $str.chars !! 0;

    if $if() && !$unless() && $validate-on && $max && $chars > $max {
      my $value = "$max";
      my $message = Message.build(:override($msg), :default('only {value} characters allowed'), :type<too-long>, :$obj, :$field, :$value, :$as, :interpolations({:count($max)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<too-long>, :options(:count($max)));
    }

    if $if() && !$unless() && $validate-on && $min && $chars < $min {
      my $value = "$min";
      my $message = Message.build(:override($msg), :default('at least {value} characters required'), :type<too-short>, :$obj, :$field, :$value, :$as, :interpolations({:count($min)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<too-short>, :options(:count($min)));
    }

    if $if() && !$unless() && $validate-on && $is && $chars != $is {
      my $value = "$is";
      my $message = Message.build(:override($msg), :default('exactly {value} characters required'), :type<wrong-length>, :$obj, :$field, :$value, :$as, :interpolations({:count($is)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<wrong-length>, :options(:count($is)));
    }

    if $if() && !$unless() && $validate-on && $in && $chars !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $message = Message.build(:override($msg), :default('{value} characters required'), :type<wrong-length>, :$obj, :$field, :$value, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<wrong-length>);
    }
  }

  method validate-acceptance(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    unless $if() && !$unless() && $validate-on && $obj."$field.name()"() {
      my $message = Message.build(:override($msg), :default('must be accepted'), :type<accepted>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<accepted>);
    }
  }

  method validate-confirmation(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."{$field.name()}_confirmation"() ~~ Empty || $obj."{$field.name()}_confirmation"() !~~ $obj."$field.name()"() {
      my $message = Message.build(:override($msg), :default('must be confirmed'), :type<confirmation>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<confirmation>);
    }
  }

  method validate-exclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$exclusion, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && !$obj."$field.name()"() || $obj."$field.name()"() (elem) $exclusion<in> {
      my $message = Message.build(:override($msg), :default('is invalid'), :type<exclusion>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<exclusion>);
    }
  }

  method validate-inclusion(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$inclusion, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."$field.name()"() ~~ Empty || (not $obj."$field.name()"() (elem) $inclusion<in>) {
      my $message = Message.build(:override($msg), :default('is invalid'), :type<inclusion>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<inclusion>);
    }
  }

  method validate-format(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Hash:D :$format, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    if $if() && !$unless() && $validate-on && $obj."$field.name()"() !~~ $format<with> {
      my $message = Message.build(:override($msg), :default('is invalid'), :type<invalid>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<invalid>);
    }
  }

  method validate-numericality(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
    my $validate-on = self.validate-on(:$obj, :$ons);

    my $gt = $param<numericality><gt>;
    my $gte = $param<numericality><gte>;
    my $lt = $param<numericality><lt>;
    my $lte = $param<numericality><lte>;
    my $in = $param<numericality><in>;

    my $number = $obj."$field.name()"().Int;

    if $if() && !$unless() && $validate-on && $gt && $number <= $gt {
      my $value = "$gt";
      my $message = Message.build(:override($msg), :default('more than {value} required'), :type<greater-than>, :$obj, :$field, :$value, :$as, :interpolations({:count($gt)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<greater-than>, :options(:count($gt)));
    }

    if $if() && !$unless() && $validate-on && $gte && $number < $gte {
      my $value = "$gte";
      my $message = Message.build(:override($msg), :default('{value} or more required'), :type<greater-than-or-equal-to>, :$obj, :$field, :$value, :$as, :interpolations({:count($gte)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<greater-than-or-equal-to>, :options(:count($gte)));
    }

    if $if() && !$unless() && $validate-on && $lt && $number >= $lt {
      my $value = "$lt";
      my $message = Message.build(:override($msg), :default('less than {value} required'), :type<less-than>, :$obj, :$field, :$value, :$as, :interpolations({:count($lt)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<less-than>, :options(:count($lt)));
    }

    if $if() && !$unless() && $validate-on && $lte && $number > $lte {
      my $value = "$lte";
      my $message = Message.build(:override($msg), :default('{value} or less required'), :type<less-than-or-equal-to>, :$obj, :$field, :$value, :$as, :interpolations({:count($lte)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type<less-than-or-equal-to>, :options(:count($lte)));
    }

    if $if() && !$unless() && $validate-on && $in && $number !~~ $in {
      my $value = "{$in.min} to {$in.max}";
      my $message = Message.build(:override($msg), :default('{value} required'), :type<inclusion>, :$obj, :$field, :$value, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<inclusion>);
    }
  }

  method validate-comparison(Mu:D :$obj, Field:D :$field, Hash:D :$ons, Block:D :$if, Block:D :$unless, Pair:D :$param, Str:D :$msg, Bool:D :$strict, Str:D :$as) {
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

    my %type-for = %(
      gt  => 'greater-than',
      gte => 'greater-than-or-equal-to',
      lt  => 'less-than',
      lte => 'less-than-or-equal-to',
      eq  => 'equal-to',
      ne  => 'other-than',
    );

    for <gt gte lt lte eq ne> -> $op {
      next unless $opts{$op}:exists;
      my $resolved = resolve($opts{$op});
      next unless $resolved.defined;
      next if cmp-ok($actual, $resolved, $op);
      my $label = $opts{$op} ~~ Str && $obj.has-attribute($opts{$op})
        ?? $opts{$op}
        !! "$resolved";
      my $message = Message.build(:override($msg), :default(%templates{$op}), :type(%type-for{$op}), :$obj, :$field, :value($label), :$as, :interpolations({:count($label)}));
      self.record-error(:$obj, :$field, :$message, :$strict, :type(%type-for{$op}), :options(:count($label)));
    }
  }

  method validate-associated(Mu:D :$obj, Str:D :$name, Hash:D :$params) {
    my $if = -> { True };
    my $unless = -> { False };
    my $msg = '';
    my $ons = {};
    my Bool $strict = False;
    my Str  $as     = '';
    for $params.pairs -> $param {
      given $param.keys.first {
        when 'on' { $ons = $param<on> }
        when /if/ { $if = $param{"if\tTrue"} }
        when /unless/ { $unless = $param{"unless\tTrue"} }
        when 'message' { $msg = $param<message> }
        when 'strict' { $strict = so $param.value }
        when 'as' { $as = ~$param.value }
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
      my $message = Message.build(:override($msg), :default('is invalid'), :type<invalid>, :$obj, :$field, :$as);
      self.record-error(:$obj, :$field, :$message, :$strict, :type<invalid>);
    }
  }

  method validate-on(Mu:D :$obj, Hash:D :$ons) {
    return True unless $ons.keys.elems;
    so $ons{$!context};
  }
}
