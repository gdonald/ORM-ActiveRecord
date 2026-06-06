
use YAMLish;

# A coder for `serialize` / `store` that stores a structured value as YAML.
# Pass it like the built-in JsonCoder: `self.serialize('prefs', YamlCoder.new)`.
class YamlCoder is export {
  method dump($value)  { save-yaml($value) }
  method load($string) {
    return $string unless $string.defined && $string.Str.chars;
    load-yaml($string.Str);
  }
}
