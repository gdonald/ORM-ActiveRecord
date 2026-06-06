unit module ORM::ActiveRecord::Support::Secrets;

# Application secrets used for signing tokens and encrypting columns. Set them
# at boot, or supply them through the environment.

my Str $secret-key-base;
my @encryption-keys;

sub secret-key-base(*@set) is export {
  if @set { $secret-key-base = @set[0].Str; return $secret-key-base }
  return $secret-key-base if $secret-key-base.defined;
  return $_ with %*ENV<AR_SECRET_KEY_BASE>;
  die "ORM::ActiveRecord: no secret key base set (call secret-key-base('...') or set AR_SECRET_KEY_BASE)";
}

# The encryption keys, primary first. Decryption tries each in turn, which is
# how key rotation works: prepend a new key and old data still decrypts.
sub encryption-keys(*@set) is export {
  if @set { @encryption-keys = @set.flat.map(*.Str); return @encryption-keys }
  return @encryption-keys if @encryption-keys.elems;
  with %*ENV<AR_ENCRYPTION_KEYS> { return .split(',').grep(*.chars) }
  with %*ENV<AR_ENCRYPTION_KEY>  { return ($_,) }
  die "ORM::ActiveRecord: no encryption keys set (call encryption-keys('...') or set AR_ENCRYPTION_KEY)";
}

sub primary-encryption-key(--> Str) is export { encryption-keys()[0] }

sub reset-secrets is export {
  $secret-key-base = Str;
  @encryption-keys = ();
}
