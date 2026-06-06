
use ORM::ActiveRecord::Type;
use ORM::ActiveRecord::Support::Crypto;
use ORM::ActiveRecord::Support::Secrets;

# Encrypts a column at rest with AES-256-CBC, authenticated with HMAC-SHA256
# (encrypt-then-MAC). The stored value is base64url( IV ++ ciphertext ++ MAC ).
#
# Deterministic mode derives the IV from the plaintext, so equal plaintexts
# encrypt to equal ciphertexts and the column stays queryable. Random mode uses
# a fresh IV each time. Decryption tries every configured key, which is how
# rotation works; a value that matches no key is returned unchanged (so a column
# can be backfilled from existing plaintext).
class EncryptedType does AttributeType is export {
  has Bool $.deterministic = False;
  has Bool $.downcase      = False;

  method cast($value) {
    return $value unless $value.defined;
    $!downcase ?? $value.Str.lc !! $value;
  }

  method serialize($value) {
    return $value unless $value.defined;
    my $plain = ($!downcase ?? $value.Str.lc !! $value.Str).encode('utf-8');
    self!encrypt($plain, primary-encryption-key());
  }

  method deserialize($value) {
    return $value unless $value.defined && $value.Str.chars;
    self!decrypt($value.Str);
  }

  method !encrypt(Blob:D $plaintext, Str:D $key --> Str) {
    my $enc-key = derive-key("enc:$key");
    my $mac-key = derive-key("mac:$key");
    my $iv = $!deterministic
      ?? hmac-sha256($mac-key, $plaintext).subbuf(0, 16)
      !! random-bytes(16);

    my $ciphertext = aes256-encrypt($enc-key, $iv, $plaintext);
    my $mac        = hmac-sha256($mac-key, $iv ~ $ciphertext);

    b64url-encode($iv ~ $ciphertext ~ $mac);
  }

  method !decrypt(Str:D $stored --> Str) {
    my $blob = try b64url-decode($stored);
    return $stored without $blob;
    return $stored if $blob.bytes < 16 + 32;

    my $iv         = $blob.subbuf(0, 16);
    my $mac        = $blob.subbuf($blob.bytes - 32);
    my $ciphertext = $blob.subbuf(16, $blob.bytes - 16 - 32);

    for encryption-keys() -> $key {
      my $mac-key = derive-key("mac:$key");
      next unless constant-time-eq(hmac-sha256($mac-key, $iv ~ $ciphertext), $mac);
      my $enc-key = derive-key("enc:$key");
      return aes256-decrypt($enc-key, $iv, $ciphertext).decode('utf-8');
    }

    $stored;
  }
}
