
use JSON::Tiny;
use ORM::ActiveRecord::Support::Crypto;
use ORM::ActiveRecord::Support::Secrets;

# Secure tokens, passwords, and signed ids. Declare these in `submethod BUILD`.
#
#   self.has-secure-token('auth_token');
#   self.has-secure-password;                       # password / password_digest
#   self.generates-token-for('password-reset', :expires-in(900), { .password_digest });
role ModelSecure is export {
  my %secure-tokens;      # class => { column => length }
  my %password-config;    # class => { attribute, iterations }
  my %token-generators;   # class => { purpose => { expires-in, block } }

  # ---- declarations ----

  method has-secure-token(Str:D $column, Int:D :$length = 24) {
    %secure-tokens{self.WHAT.^name}{$column} = $length;
    self;
  }

  method has-secure-password(Str:D :$attribute = 'password', Int:D :$iterations = 100000) {
    %password-config{self.WHAT.^name} = { :$attribute, :$iterations };
    self.attribute($attribute);
    self.attribute($attribute ~ '_confirmation');
    self;
  }

  method generates-token-for(Str:D $purpose, &block, :$expires-in) {
    %token-generators{self.WHAT.^name}{$purpose} = { :$expires-in, :&block };
    self;
  }

  method !secure-lookup(%store) {
    for self.^mro -> $ancestor {
      return %store{$ancestor.^name} if %store{$ancestor.^name}:exists;
    }
    Nil;
  }

  method secure-token(Int:D :$length = 24 --> Str) { urlsafe-token($length) }

  # ---- save-time hooks ----

  method apply-secure-tokens {
    my %tokens = self!secure-lookup(%secure-tokens) // return;
    for %tokens.kv -> $column, $length {
      next if (self.attrs{$column} // '').Str.chars;
      self.attrs{$column} = urlsafe-token($length);
    }
  }

  method regenerate-secure-token(Str:D $column) {
    my %tokens = self!secure-lookup(%secure-tokens) // return;
    self.attrs{$column} = urlsafe-token(%tokens{$column} // 24);
    self.save;
  }

  method apply-secure-password {
    my %config = self!secure-lookup(%password-config) // return;
    my $value  = self.attrs{%config<attribute>};
    return unless $value.defined && $value.Str.chars;
    self.attrs{%config<attribute> ~ '_digest'} =
      password-digest($value.Str, iterations => %config<iterations>);
  }

  method authenticate(Str:D $password) {
    my %config = self!secure-lookup(%password-config) // return False;
    my $digest = self.attrs{%config<attribute> ~ '_digest'};
    return False unless $digest.defined && $digest.Str.chars;
    password-verify($password, $digest.Str) ?? self !! False;
  }

  # ---- signing ----

  method !sign-payload(%payload --> Str) {
    my $body = b64url-encode(to-json(%payload).encode('utf-8'));
    my $sig  = b64url-encode(hmac-sha256(secret-key-base().encode('utf-8'), $body.encode('utf-8')));
    "$body--$sig";
  }

  method !verify-payload(Str:D $token) {
    my @parts = $token.split('--');
    return Nil unless @parts.elems == 2;

    my $expected = b64url-encode(hmac-sha256(secret-key-base().encode('utf-8'), @parts[0].encode('utf-8')));
    return Nil unless constant-time-eq(@parts[1].encode('utf-8'), $expected.encode('utf-8'));

    from-json(b64url-decode(@parts[0]).decode('utf-8'));
  }

  method signed-id(:$expires-in, Str:D :$purpose = 'default' --> Str) {
    my %payload = id => self.id, purpose => "signed-id:$purpose";
    %payload<exp> = time + $expires-in.Int if $expires-in.defined;
    self!sign-payload(%payload);
  }

  method find-signed(Str:D $token, Str:D :$purpose = 'default') {
    my $payload = self!verify-payload($token);
    return Nil without $payload;
    return Nil unless $payload<purpose> eq "signed-id:$purpose";
    return Nil if $payload<exp>.defined && time >= $payload<exp>;
    self.where({ id => $payload<id> }).first;
  }

  method find-signed-or-die(Str:D $token, Str:D :$purpose = 'default') {
    self.find-signed($token, :$purpose) // die "find-signed-or-die: invalid or expired token";
  }

  # ---- purpose-scoped tokens that invalidate when the embedded value changes ----

  method generate-token-for(Str:D $purpose --> Str) {
    my %gen = (self!secure-lookup(%token-generators) // {}){$purpose}
      // die "generate-token-for: no generator for '$purpose'";

    my %payload = id => self.id, purpose => "token-for:$purpose";
    %payload<exp> = time + %gen<expires-in>.Int if %gen<expires-in>.defined;
    %payload<val> = self!embedded-value(self, %gen<block>);
    self!sign-payload(%payload);
  }

  method !embedded-value($record, &block --> Str) {
    b64url-encode(hmac-sha256(secret-key-base().encode('utf-8'),
                              (block($record) // '').Str.encode('utf-8')));
  }

  method find-by-token-for(Str:D $purpose, Str:D $token) {
    my $payload = self!verify-payload($token);
    return Nil without $payload;
    return Nil unless $payload<purpose> eq "token-for:$purpose";
    return Nil if $payload<exp>.defined && time >= $payload<exp>;

    my $record = self.where({ id => $payload<id> }).first;
    return Nil without $record;

    my %gen = (self!secure-lookup(%token-generators) // {}){$purpose};
    return Nil without %gen;

    my $current = self!embedded-value($record, %gen<block>);
    return Nil unless constant-time-eq($current.encode('utf-8'), ($payload<val> // '').Str.encode('utf-8'));

    $record;
  }
}
