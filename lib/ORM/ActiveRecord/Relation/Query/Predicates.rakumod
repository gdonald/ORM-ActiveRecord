
use ORM::ActiveRecord::Support::Utils;

role QueryPredicates is export {
  method is-any(--> Bool)   { not self.is-empty }
  method is-empty(--> Bool) {
    return True if self.is-none-value;
    self.count == 0;
  }
  method is-none(--> Bool)  { self.is-none-value.so }
  method is-one(--> Bool)   {
    return False if self.is-none-value;
    self.count == 1;
  }
  method is-many(--> Bool)  {
    return False if self.is-none-value;
    self.count > 1;
  }

  method cache-key(--> Str) {
    my $stmt = self.build-select-stmt;
    my $fingerprint = $stmt.sql ~ "\0" ~ $stmt.binds.map(*.gist).join("\0");
    self.table-of ~ '/query-' ~ Utils.fnv1a-hex($fingerprint);
  }

  method cache-version(--> Str) {
    return '0' if self.is-none-value;
    return Str unless self.fields-of.first({ .name eq 'updated_at' }).so;
    my $count = self.count;
    return '0' if $count == 0;
    my $max = self.maximum('updated_at');
    my $ts = $max.defined ?? $max.Str !! 'na';
    "$count-$ts";
  }

  method cache-key-with-version(--> Str) {
    my $v = self.cache-version;
    $v.defined ?? self.cache-key ~ '-' ~ $v !! self.cache-key;
  }

  method exists {
    self.count > 0;
  }
}
