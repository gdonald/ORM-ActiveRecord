
use ORM::ActiveRecord::Errors::X;

role ModelAttributes is export {
  method assign-attributes(%attrs) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if self.is-destroyed;
    for %attrs.kv -> $key, $val { self.attrs{$key} = $val }
    self;
  }

  method attributes() is rw {
    my $model = self;
    Proxy.new(
      FETCH => method () { %($model.attrs) },
      STORE => method ($new) {
        $model.assign-attributes($new);
        %($model.attrs);
      }
    );
  }

  method read-attribute(Str:D $name) {
    self.attrs{$name};
  }

  method write-attribute(Str:D $name, $value) {
    die X::FrozenRecord.new(model => self.WHAT.^name) if self.is-destroyed;
    self.attrs{$name} = $value;
    $value;
  }

  method AT-KEY(Str:D $key) is rw {
    if self.is-destroyed {
      my $model = self;
      return Proxy.new(
        FETCH => method () { $model.attrs{$key} },
        STORE => method ($) {
          die X::FrozenRecord.new(model => $model.WHAT.^name);
        }
      );
    }
    self.attrs{$key};
  }

  method EXISTS-KEY(Str:D $key --> Bool) { self.attrs{$key}:exists }

  method has-attribute(Str:D $name --> Bool) {
    so self.fields.first({ .name eq $name });
  }

  method is-attribute-present(Str:D $name --> Bool) {
    return False unless self.attrs{$name}:exists;
    my $v = self.attrs{$name};
    return False without $v;
    return False if $v ~~ Bool && !$v;
    return False if $v ~~ Str && $v ~~ /^ \s* $/;
    return False if $v ~~ Positional && !$v.elems;
    return False if $v ~~ Associative && !$v.elems;
    True;
  }

  method attribute-names {
    self.fields.map(*.name).list;
  }
}
