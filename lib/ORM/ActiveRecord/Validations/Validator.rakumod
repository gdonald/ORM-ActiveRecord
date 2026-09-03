
use ORM::ActiveRecord::Schema::Field;

# The class a validator belongs to is fixed, so the name every validation
# compares against is built once rather than on each pass over the record.
role OwnedByClass {
  has Str $!klass-name;
  method klass-name(--> Str) { $!klass-name //= self.klass.raku }
}

class Validator is export does OwnedByClass {
  has $.klass;
  has Field $.field;
  has Hash $.params;

  has %!options;
  has Bool $!options-parsed = False;

  # The options a validator was declared with never change, so they are read
  # out of `params` once rather than on every validation of every record.
  method options(--> Hash) {
    return %!options if $!options-parsed;

    %!options = %(
      ons         => {},
      cond-if     => -> { True },
      cond-unless => -> { False },
      exclusion   => {},
      inclusion   => {},
      format      => {},
      msg         => '',
      allow-nil   => False,
      allow-blank => False,
      strict      => False,
      as          => '',
    );

    # `.pairs` explicitly: the attribute is scalar-containerised, so iterating
    # it bare would yield the whole hash as one item rather than its pairs.
    for $!params.pairs -> $param {
      given $param.keys.first {
        when 'on' { %!options<ons> = $param<on> }
        when /if/ { %!options<cond-if> = $param{"if\tTrue"} }
        when /unless/ { %!options<cond-unless> = $param{"unless\tTrue"} }
        when 'message' { %!options<msg> = $param<message> }
        when 'exclusion' { %!options<exclusion> = $param<exclusion> }
        when 'inclusion' { %!options<inclusion> = $param<inclusion> }
        when 'format' { %!options<format> = $param<format> }
        when 'allow-nil' | 'allow_nil' { %!options<allow-nil> = so $param.value }
        when 'allow-blank' | 'allow_blank' { %!options<allow-blank> = so $param.value }
        when 'strict' { %!options<strict> = so $param.value }
        when 'as' { %!options<as> = ~$param.value }
      }
    }

    $!options-parsed = True;
    %!options;
  }
}

class EachValidator is export does OwnedByClass {
  has $.klass;
  has @.fields of Str;
  has Block $.block;
  has Hash $.params;

  has %!options;
  has Bool $!options-parsed = False;

  method options(--> Hash) {
    return %!options if $!options-parsed;

    %!options = %(
      ons         => {},
      cond-if     => -> { True },
      cond-unless => -> { False },
      strict      => False,
    );

    for $!params.pairs -> $param {
      given $param.keys.first {
        when 'on'     { %!options<ons> = $param<on> }
        when 'strict' { %!options<strict> = so $param.value }
        when /if/     { %!options<cond-if> = $param{"if\tTrue"} }
        when /unless/ { %!options<cond-unless> = $param{"unless\tTrue"} }
      }
    }

    $!options-parsed = True;
    %!options;
  }
}

class WithValidator is export does OwnedByClass {
  has $.klass;
  has $.validator;
  has Hash $.options;
}

class AssociatedValidator is export does OwnedByClass {
  has $.klass;
  has Str $.name;
  has Hash $.params;
}
