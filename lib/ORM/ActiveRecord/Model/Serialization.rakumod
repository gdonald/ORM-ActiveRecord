
use JSON::Tiny;

role ModelSerialization is export {
  method to-param() {
    return Str if self.id == 0;
    self.id.Str;
  }

  method to-key() {
    return Nil if self.id == 0;
    [self.id];
  }

  method cache-key(--> Str) {
    return self.all.cache-key unless self.DEFINITE;
    my $table = self.table-name;
    return "$table/new" if self.id == 0;
    "$table/" ~ self.id;
  }

  method cache-version() {
    return self.all.cache-version unless self.DEFINITE;
    return Str unless self.attrs<updated_at>:exists && self.attrs<updated_at>.defined;
    self.attrs<updated_at>.Str;
  }

  method cache-key-with-version(--> Str) {
    return self.all.cache-key-with-version unless self.DEFINITE;
    my $v = self.cache-version;
    $v.defined ?? self.cache-key ~ '-' ~ $v !! self.cache-key;
  }

  method filter-attribute(*@names) {
    self.filter-attributes.append(@names.map(*.Str));
    self;
  }

  method !is-filtered(Str:D $name --> Bool) {
    so self.filter-attributes.first({ ~$_ eq $name });
  }

  method serializable-hash(:$only = (), :$except = (), :$methods = () --> Hash) {
    my @only-s   = self!list-of-str($only);
    my @except-s = self!list-of-str($except);
    my @methods-s = self!list-of-str($methods);
    my %out;
    for self.attribute-names -> $name {
      next if @only-s.elems   && $name !(elem) @only-s;
      next if @except-s.elems && $name (elem) @except-s;
      %out{$name} = self.attrs{$name};
    }
    for @methods-s -> $name {
      %out{$name} = self."$name"();
    }
    %out;
  }

  method !list-of-str($v) {
    return () without $v;
    return $v.list.map(*.Str) if $v ~~ Iterable;
    ($v.Str,);
  }

  method as-json(*%opts --> Hash) {
    self!coerce-for-json(self.serializable-hash(|%opts));
  }

  method to-json(*%opts --> Str) {
    to-json(self.as-json(|%opts));
  }

  method !coerce-for-json($value) {
    given $value {
      when DateTime    { $value.Str }
      when Date        { $value.Str }
      when Hash        {
        my %h;
        for $value.kv -> $k, $v { %h{$k} = self!coerce-for-json($v) }
        %h;
      }
      when Positional  { $value.map({ self!coerce-for-json($_) }).list }
      default          { $value }
    }
  }

  method attribute-for-inspect(Str:D $name --> Str) {
    return '[FILTERED]' if self!is-filtered($name);
    my $value = self.attrs{$name};
    return 'Nil' without $value;
    given $value {
      when Str {
        my $s = $value.chars > 50 ?? $value.substr(0, 50) ~ '...' !! $value;
        '"' ~ $s ~ '"';
      }
      when DateTime | Date { '"' ~ $value.Str ~ '"' }
      when Bool            { $value ?? 'True' !! 'False' }
      default              { $value.Str }
    }
  }

  method inspect(--> Str) {
    my $class-name = self.WHAT.^name;
    my @parts;
    for self.attribute-names -> $name {
      @parts.push: $name ~ ': ' ~ self.attribute-for-inspect($name);
    }
    '#<' ~ $class-name ~ ' ' ~ @parts.join(', ') ~ '>';
  }

  method gist(--> Str) {
    return callsame() unless self.DEFINITE;
    self.inspect;
  }
}
