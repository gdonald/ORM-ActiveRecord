#unit class ORM::ActiveRecord::Validator;

use ORM::ActiveRecord::Error;

class Validator is export {
  my @.validators of Validator;

  has $.klass;
  has Str $.field;
  has Hash $.params;

  submethod BUILD(:$!klass, :$!field, :$!params) {

  }

  method validate($obj) {
    for Validator.validators -> $validator {
      next unless $obj.^name eq $validator.klass.perl;

      for $validator.params -> $param {
        my Str $name = $param.keys.first;

        if $name eq 'presence' && $obj."$validator.field()"() ~~ Empty {
          my $e = Error.new(:field($validator.field), :message('must be present'));
          $obj.errors.push($e);
        }

        if $name eq 'length' {
          if $param<length><maximum> {
            if $obj."$validator.field()"().chars > $param<length><maximum> {
              my $e = Error.new(:field($validator.field), :message("less than $param<length><maximum> characters required"));
              $obj.errors.push($e);
            }
          }

          if $param<length><minimum> {
            if $obj."$validator.field()"().chars < $param<length><minimum> {
              my $e = Error.new(:field($validator.field), :message("at least $param<length><minimum> characters required"));
              $obj.errors.push($e);
            }
          }
        }
      }
    }
  }
}
