
use ORM::ActiveRecord::Type::Encrypted;

# Column encryption. Declare in `submethod BUILD`:
#
#   self.encrypts('ssn', :deterministic);     # queryable
#   self.encrypts('notes');                    # random IV, not queryable
#   self.encrypts('email', :deterministic, :downcase);
role ModelEncryption is export {
  my %encrypted-config;   # class => { column => { deterministic, downcase } }

  method encrypts(Str:D $column, Bool:D :$deterministic = False, Bool:D :$downcase = False) {
    %encrypted-config{self.WHAT.^name}{$column} = { :$deterministic, :$downcase };
    self.attribute($column, EncryptedType.new(:$deterministic, :$downcase));
    self;
  }

  method !encryption-merged {
    my %merged;
    for self.^mro.reverse -> $ancestor {
      with %encrypted-config{$ancestor.^name} -> %defs {
        %merged{.key} = .value for %defs;
      }
    }
    %merged;
  }

  method encrypted-attrs {
    self!encryption-merged.keys.list;
  }

  method encrypted-deterministic-attrs {
    self!encryption-merged.grep({ .value<deterministic> }).map(*.key).list;
  }

  # The stored ciphertext for a plaintext value, for building queries against a
  # deterministically-encrypted column.
  method encrypt-value(Str:D $column, $plaintext) {
    my %config = self!encryption-merged;
    return $plaintext without %config{$column};
    EncryptedType.new(|%config{$column}).serialize($plaintext);
  }

  # Re-save every record, encrypting any column that is still plaintext.
  # Backfill: rewrite every row so a column that was stored as plaintext before
  # `encrypts` was declared is stored encrypted. The attribute itself does not
  # change, only what a write makes of it, so each encrypted column is marked
  # dirty to put it in the UPDATE.
  method encrypt-existing {
    my @columns = self.encrypted-attrs;

    for self.all.perform -> $record {
      $record.attribute-will-change($_) for @columns;
      $record.save;
    }
  }
}
