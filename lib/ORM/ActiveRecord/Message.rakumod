
use ORM::ActiveRecord::Field;

class Message is export {

  method build(Str:D :$template, Mu:D :$obj, Field:D :$field, Str:D :$value = '') {
    return $template
            .subst(/\{model\}/, $obj.^name)
            .subst(/\{attribute\}/, $field.name)
            .subst(/\{value\}/, $value);
  }
}
