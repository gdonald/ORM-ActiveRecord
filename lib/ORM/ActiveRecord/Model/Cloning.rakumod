
role ModelCloning is export {
  method dup() {
    my $class = self.WHAT;
    my %attrs-copy;
    for self.attrs.kv -> $key, $val {
      next if $key eq any('id', 'created_at', 'updated_at');
      %attrs-copy{$key} = $val;
    }
    $class.new(:id(0), :record({ attrs => %attrs-copy }));
  }

  method clone() {
    my $class = self.WHAT;
    my %attrs-copy;
    for self.attrs.kv -> $key, $val { %attrs-copy{$key} = $val }
    my $new = $class.new(:id(self.id), :record({ attrs => %attrs-copy }));
    $new.make-readonly if self.is-readonly;
    $new;
  }
}
