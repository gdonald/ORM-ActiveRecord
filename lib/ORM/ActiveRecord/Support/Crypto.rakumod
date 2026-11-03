unit module ORM::ActiveRecord::Support::Crypto;

use NativeCall;
use OpenSSL::Digest;
use OpenSSL::CryptTools;
use OpenSSL::NativeLib;
use Base64;
use ORM::ActiveRecord::Support::Environment;

constant PRODUCTION-PASSWORD-ITERATIONS = 100000;
constant MINIMUM-PASSWORD-ITERATIONS    = 1;

sub EVP_sha256(--> Pointer) is native(&crypto-lib) { * }

sub PKCS5_PBKDF2_HMAC(Blob, int32, Blob, int32, int32, Pointer, int32, Buf --> int32)
  is native(&crypto-lib) { * }

sub random-bytes(Int:D $count --> Blob) is export {
  my $fh = '/dev/urandom'.IO.open(:bin, :r);
  LEAVE $fh.close;
  $fh.read($count);
}

# A URL-safe, unpadded random token.
sub urlsafe-token(Int:D $bytes = 24 --> Str) is export {
  encode-base64(random-bytes($bytes), :str, :uri).subst('=', '', :g);
}

sub b64url-encode(Blob:D $blob --> Str) is export {
  encode-base64($blob, :str, :uri).subst('=', '', :g);
}

sub b64url-decode(Str:D $string --> Blob) is export {
  my $padded = $string ~ ('=' x ((4 - $string.chars % 4) % 4));
  decode-base64($padded, :uri, :bin);
}

# HMAC-SHA256 (RFC 2104), block size 64 bytes.
sub hmac-sha256(Blob:D $key is copy, Blob:D $message --> Blob) is export {
  $key = sha256($key) if $key.bytes > 64;
  my $padded = Buf.new($key);
  $padded.push(0) while $padded.bytes < 64;

  my $ipad = Buf.new((^64).map({ $padded[$_] +^ 0x36 }));
  my $opad = Buf.new((^64).map({ $padded[$_] +^ 0x5c }));

  sha256($opad ~ sha256($ipad ~ $message));
}

sub pbkdf2-sha256(Blob:D $password, Blob:D $salt, Int:D $iterations, Int:D $length --> Blob) is export {
  my $output = Buf.allocate($length);

  PKCS5_PBKDF2_HMAC($password, $password.bytes, $salt, $salt.bytes,
                    $iterations, EVP_sha256(), $length, $output)
    or die "PKCS5_PBKDF2_HMAC failed";

  $output;
}

# Timing-safe comparison.
sub constant-time-eq(Blob:D $a, Blob:D $b --> Bool) is export {
  return False if $a.bytes != $b.bytes;
  my $diff = 0;
  $diff = $diff +| ($a[$_] +^ $b[$_]) for ^$a.bytes;
  $diff == 0;
}

sub aes256-encrypt(Blob:D $key, Blob:D $iv, Blob:D $plaintext --> Blob) is export {
  encrypt($plaintext, :$key, :$iv, :aes256);
}

sub aes256-decrypt(Blob:D $key, Blob:D $iv, Blob:D $ciphertext --> Blob) is export {
  decrypt($ciphertext, :$key, :$iv, :aes256);
}

# Derive a 32-byte key from an arbitrary secret string.
sub derive-key(Str:D $secret --> Blob) is export {
  sha256($secret.encode('utf-8'));
}

sub default-password-iterations(--> Int) is export {
  current-env() eq 'test' ?? MINIMUM-PASSWORD-ITERATIONS !! PRODUCTION-PASSWORD-ITERATIONS;
}

sub password-digest(Str:D $password, Int:D :$iterations = default-password-iterations() --> Str) is export {
  my $salt = random-bytes(16);
  my $hash = pbkdf2-sha256($password.encode('utf-8'), $salt, $iterations, 32);
  ('pbkdf2-sha256', $iterations, b64url-encode($salt), b64url-encode($hash)).join('$');
}

sub password-verify(Str:D $password, Str:D $digest --> Bool) is export {
  my @parts = $digest.split('$');
  return False unless @parts.elems == 4 && @parts[0] eq 'pbkdf2-sha256';

  my $iterations = @parts[1].Int;
  my $salt       = b64url-decode(@parts[2]);
  my $expected   = b64url-decode(@parts[3]);
  my $actual     = pbkdf2-sha256($password.encode('utf-8'), $salt, $iterations, $expected.bytes);

  constant-time-eq($actual, $expected);
}
