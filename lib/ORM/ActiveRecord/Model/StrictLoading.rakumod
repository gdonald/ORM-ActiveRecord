
role ModelStrictLoading is export {
  my %class-default;

  method strict-loading-by-default(Bool:D $on = True) {
    %class-default{self.WHAT.^name} = $on;
    self;
  }

  method is-strict-loading-by-default(--> Bool) {
    for self.WHAT.^mro -> $cls {
      next if $cls === Mu | Any;
      my $n = $cls.^name;
      return True if %class-default{$n} // False;
    }
    False;
  }
}
