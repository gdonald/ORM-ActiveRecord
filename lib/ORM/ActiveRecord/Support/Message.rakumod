
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Utils;

class Message is export {

  method build(Str:D :$template, Mu:D :$obj, Field:D :$field, Str:D :$value = '', Str :$as) {
    my $attr-name = $as.defined && $as ne '' ?? $as !! $field.name;

    return $template
            .subst(/\{model\}/, Utils.base-name($obj.^name))
            .subst(/\{attribute\}/, $attr-name)
            .subst(/\{value\}/, $value);
  }
}
