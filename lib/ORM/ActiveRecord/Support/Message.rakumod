
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Support::I18n;

class Message is export {

  method interpolate(Str:D $template is copy, %tokens --> Str) {
    for %tokens.kv -> $key, $val {
      next unless $val.defined;

      $template = $template.subst('{' ~ $key ~ '}', ~$val, :g);
    }

    $template;
  }

  method resolve-template(:$override, :$default, :$type, :$model, :$attribute --> Str) {
    return $override if $override.defined && $override ne '';

    my $located = $type.defined && $type ne ''
      ?? I18n.error-template(:$type, :$model, :$attribute)
      !! Str;

    return $located if $located.defined && $located ne '';

    $default // 'is invalid';
  }

  method build(Str :$template, Str :$override, Str :$default, Str :$type,
               Mu:D :$obj!, Field:D :$field!, Str :$value = '', Str :$as, :%interpolations --> Str) {
    my $model     = Utils.base-name($obj.^name);
    my $attr-name = $as.defined && $as ne '' ?? $as !! $field.name;

    my $resolved = $template.defined && $template ne ''
      ?? $template
      !! self.resolve-template(:$override, :$default, :$type, :model($model.lc), :attribute($field.name));

    my %tokens =
      model     => $model,
      attribute => $attr-name,
      value     => $value,
      |%interpolations,
    ;

    self.interpolate($resolved, %tokens);
  }
}
