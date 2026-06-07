
# Attribute normalisation. Declare in `submethod BUILD`:
#
#   self.normalizes('email', :with(-> $v { $v.trim.lc }));
#   self.normalizes('first-name', 'last-name', :with(-> $v { $v.trim }));
#
# The block runs on the attribute before validation and save, so the stored
# value is always normalised, and on values used to query a normalised column
# so a lookup matches what was stored.
role ModelNormalization is export {
  my %normalizers;   # class => { attr => block }

  method normalizes(*@attrs, :&with!) {
    %normalizers{self.WHAT.^name}{$_} = &with for @attrs;
    self;
  }

  method !normalizers-merged {
    my %merged;
    for self.^mro.reverse -> $ancestor {
      with %normalizers{$ancestor.^name} -> %defs {
        %merged{.key} = .value for %defs;
      }
    }
    %merged;
  }

  method normalized-attrs { self!normalizers-merged.keys.list }

  method apply-normalizations {
    my %norms = self!normalizers-merged;
    for %norms.kv -> $attr, &block {
      next unless self.attrs{$attr}:exists && self.attrs{$attr}.defined;
      self.attrs{$attr} = block(self.attrs{$attr});
    }
  }

  method normalize-value-for(Str:D $attr, $value) {
    my %norms = self!normalizers-merged;
    return $value without %norms{$attr};
    return $value unless $value.defined;
    %norms{$attr}($value);
  }
}
