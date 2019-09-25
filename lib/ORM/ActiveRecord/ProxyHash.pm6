
class ProxyHash does Associative {
  has %!hash handles <EXISTS-KEY DELETE-KEY push iterator list kv keys values>;
  my Bool $.dirty;

  method gist { %!hash.gist }
  method Str  { %!hash.Str }
  method is-dirty(--> Bool) { ::?CLASS.dirty }
  method clean { ::?CLASS.dirty = False }

  multi method AT-KEY (::?CLASS:D: $key) is rw {
    my $element := %!hash{$key};

    Proxy.new(
      FETCH => method () { $element },
      STORE => method ($value) {
        ::?CLASS.dirty = True;
        $element = $value;
      }
    );
  }
}
