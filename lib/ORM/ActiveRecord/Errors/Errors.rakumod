
use ORM::ActiveRecord::Errors::Error;
use ORM::ActiveRecord::Schema::Field;

class Errors {
  has Error @.errors;

  my %DEFAULT-TEMPLATES =
    blank                       => 'must be present',
    present                     => 'must be blank',
    taken                       => 'has already been taken',
    too-short                   => 'is too short',
    too-long                    => 'is too long',
    wrong-length                => 'is the wrong length',
    inclusion                   => 'is not included in the list',
    exclusion                   => 'is reserved',
    invalid                     => 'is invalid',
    confirmation                => 'must be confirmed',
    accepted                    => 'must be accepted',
    not-a-number                => 'is not a number',
    not-an-integer              => 'must be an integer',
    greater-than                => 'must be greater than {count}',
    greater-than-or-equal-to    => 'must be greater than or equal to {count}',
    less-than                   => 'must be less than {count}',
    less-than-or-equal-to       => 'must be less than or equal to {count}',
    equal-to                    => 'must be equal to {count}',
    other-than                  => 'must be other than {count}',
    odd                         => 'must be odd',
    even                        => 'must be even',
    empty                       => "can't be empty",
  ;

  method push(Error:D $error) {
    @!errors.push($error);
  }

  method add(Str:D $attribute, $type is copy = 'invalid', :$message is copy, *%options) {
    $type = $type.key if $type ~~ Pair;
    $type = ~$type;

    if $type ~~ /\s/ {
      $message //= $type;
      $type     = 'invalid';
    }

    my $template = $message // %DEFAULT-TEMPLATES{$type} // 'is invalid';
    my $msg      = self!interpolate($template, $attribute, %options);
    my $field    = Field.new(:name($attribute), :type('attribute'));

    @!errors.push(Error.new(:$field, :message($msg), :$type, :%options));
  }

  method import(Error:D $error) {
    @!errors.push($error);
  }

  method delete(Str:D $attribute, $type? is copy, *%options) {
    my @removed;
    my @kept;

    for @!errors -> $e {
      my Bool $match = $e.attribute eq $attribute;

      if $match && $type.defined {
        my $t = $type ~~ Pair ?? $type.key !! ~$type;
        $match = $e.type eq $t;
      }

      if $match {
        @removed.push($e);
      } else {
        @kept.push($e);
      }
    }

    @!errors = @kept;

    @removed;
  }

  method clear {
    @!errors = ();
  }

  method full-messages {
    @!errors.map(*.full-message);
  }

  method full-messages-for(Str:D $attribute) {
    @!errors.grep(*.attribute eq $attribute).map(*.full-message);
  }

  method full-message(Str:D $attribute, Str:D $message --> Str) {
    return $message if $attribute eq 'base';

    "$attribute $message";
  }

  method details {
    my %d;

    for @!errors -> $e {
      %d{$e.attribute}.push($e.detail);
    }

    %d;
  }

  method where(Str :$attribute, :$type, *%options) {
    @!errors.grep({ .match(:$attribute, :$type, |%options) });
  }

  method is-of-kind(Str:D $attribute, $type = 'invalid' --> Bool) {
    @!errors.grep({ .match(:$attribute, :$type) }).elems.so;
  }

  method is-added(Str:D $attribute, $type is copy = 'invalid', :$message, *%options --> Bool) {
    $type = $type.key if $type ~~ Pair;
    $type = ~$type;

    if $type ~~ /\s/ {
      return @!errors.grep({ .attribute eq $attribute && .message eq $type }).elems.so;
    }

    if $message.defined {
      return @!errors.grep({ .attribute eq $attribute && .type eq $type && .message eq $message }).elems.so;
    }

    @!errors.grep({ .match(:$attribute, :$type, |%options) }).elems.so;
  }

  method size( --> Int )  { @!errors.elems }
  method count( --> Int ) { @!errors.elems }
  method elems( --> Int ) { @!errors.elems }
  method is-any( --> Bool ) { @!errors.elems > 0 }
  method is-empty( --> Bool ) { @!errors.elems == 0 }

  method group-by-attribute {
    my %grouped;

    for @!errors -> $e {
      %grouped{$e.attribute}.push($e);
    }

    %grouped;
  }

  method objects {
    @!errors.list;
  }

  method messages {
    my %m;

    for @!errors -> $e {
      %m{$e.attribute}.push($e.message);
    }

    %m;
  }

  method attribute-names {
    @!errors.map(*.attribute).unique.list;
  }

  method merge(Errors:D $other) {
    for $other.errors -> $e {
      @!errors.push($e);
    }

    self;
  }

  method AT-POS(Int:D $i)         { @!errors[$i] }
  method EXISTS-POS(Int:D $i)     { @!errors[$i]:exists }
  method list                     { @!errors.list }

  submethod FALLBACK(Str:D $name, *@rest) {
    @!errors.map({ .message if .attribute eq $name });
  }

  method !interpolate(Str:D $template, Str:D $attribute, %options --> Str) {
    my $out = $template;

    $out = $out.subst(/\{attribute\}/, $attribute, :g);

    for %options.kv -> $k, $v {
      next unless $v.defined;

      my $token = '{' ~ $k ~ '}';
      $out = $out.subst($token, ~$v, :g);
    }

    $out;
  }
}
