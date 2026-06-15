
class I18n is export {
  my %stores;
  my Str $current-locale = 'en';
  my Str $default-locale = 'en';

  method locale(--> Str) { $current-locale }

  method set-locale(Str:D $locale --> Str) { $current-locale = $locale }

  method default-locale(--> Str) { $default-locale }

  method set-default-locale(Str:D $locale --> Str) { $default-locale = $locale }

  method available-locales { %stores.keys.sort.list }

  method with-locale(Str:D $locale, &block) {
    my $previous = $current-locale;
    $current-locale = $locale;

    LEAVE { $current-locale = $previous }

    block();
  }

  method store(Str:D $locale, %translations --> Nil) {
    %stores{$locale} = self!deep-merge(%stores{$locale} // {}, %translations);
  }

  method translations(Str:D $locale) { (%stores{$locale} // {}).Hash }

  method reset(--> Nil) {
    %stores = ();
    $current-locale = 'en';
    $default-locale = 'en';
  }

  method error-template(:$type!, :$model, :$attribute --> Str) {
    return Str unless $type.defined;

    my @paths = self!error-paths(:$model, :$attribute, :type(~$type));

    for ($current-locale, $default-locale).unique -> $locale {
      my %tree := %stores{$locale} // {};
      next unless %tree.elems;

      for @paths -> @path {
        my $found = self!dig(%tree, @path);
        return $found if $found.defined && $found ~~ Str;
      }
    }

    Str;
  }

  method !error-paths(:$model, :$attribute, :$type) {
    my @paths;

    if $model.defined && $model ne '' {
      if $attribute.defined && $attribute ne '' {
        @paths.push: ['activerecord', 'errors', 'models', $model, 'attributes', $attribute, $type];
      }

      @paths.push: ['activerecord', 'errors', 'models', $model, $type];
    }

    @paths.push: ['activerecord', 'errors', 'messages', $type];

    if $attribute.defined && $attribute ne '' {
      @paths.push: ['errors', 'attributes', $attribute, $type];
    }

    @paths.push: ['errors', 'messages', $type];

    @paths;
  }

  method !dig(%tree, @path) {
    my $node = %tree;

    for @path -> $key {
      return Nil unless $node ~~ Associative;
      return Nil unless $node{$key}:exists;

      $node = $node{$key};
    }

    $node ~~ Str ?? $node !! Nil;
  }

  method !deep-merge(%a, %b) {
    my %out = %a;

    for %b.kv -> $key, $val {
      if $val ~~ Associative && (%out{$key}:exists) && %out{$key} ~~ Associative {
        %out{$key} = self!deep-merge(%out{$key}, $val);
      } else {
        %out{$key} = $val;
      }
    }

    %out;
  }
}
