
role ModelSuppressor is export {
  my %suppression-depth;

  method suppress(&block) {
    my $name = self.WHAT.^name;
    %suppression-depth{$name} = (%suppression-depth{$name} // 0) + 1;
    LEAVE %suppression-depth{$name}--;
    block();
  }

  method is-suppressed(--> Bool) {
    for self.WHAT.^mro -> $cls {
      next if $cls === Mu | Any;
      my $n = $cls.^name;
      return True if (%suppression-depth{$n} // 0) > 0;
    }
    False;
  }
}
