use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::Crypto;

sub hex(Blob:D $bytes --> Str) { $bytes.list».fmt('%02x').join }

describe 'hmac-sha256', {
  it 'matches RFC 4231 test case 1', {
    expect(hex(hmac-sha256(Blob.new(0x0b xx 20), 'Hi There'.encode)))
      .to.eq('b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
  }

  it 'matches RFC 4231 test case 2', {
    expect(hex(hmac-sha256('Jefe'.encode, 'what do ya want for nothing?'.encode)))
      .to.eq('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
  }
}

describe 'pbkdf2-sha256', {
  it 'matches the 1-iteration vector', {
    expect(hex(pbkdf2-sha256('password'.encode, 'salt'.encode, 1, 32)))
      .to.eq('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
  }

  it 'matches the 2-iteration vector', {
    expect(hex(pbkdf2-sha256('password'.encode, 'salt'.encode, 2, 32)))
      .to.eq('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  }

  it 'matches the 4096-iteration vector', {
    expect(hex(pbkdf2-sha256('password'.encode, 'salt'.encode, 4096, 32)))
      .to.eq('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  }

  it 'matches the RFC 7914 64-byte vector', {
    expect(hex(pbkdf2-sha256('passwd'.encode, 'salt'.encode, 1, 64)))
      .to.eq('55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783');
  }
}

describe 'password digests', {
  let(:stored-digest, { 'pbkdf2-sha256$100000$c2FsdA$WPyKFsPP12hgXBa2v7jdiHlEI7-_nj6yqOPUyR0tsF8' });

  it 'verifies the right password against a stored 100,000-iteration digest', {
    expect(password-verify('correct horse', stored-digest)).to.be-truthy;
  }

  it 'rejects the wrong password against a stored 100,000-iteration digest', {
    expect(password-verify('wrong', stored-digest)).to.be-falsy;
  }

  it 'uses one iteration in the test environment', {
    expect(password-digest('correct horse').starts-with('pbkdf2-sha256$1$')).to.be-truthy;
  }

  it 'defaults to 100,000 iterations outside the test environment', {
    temp %*ENV<AR_ENV> = 'production';
    expect(default-password-iterations()).to.eq(100000);
  }
}

describe 'base64url', {
  let(:bytes, { Blob.new(0, 1, 2, 250, 251, 252, 253, 254, 255) });

  it 'round-trips bytes', {
    expect(hex(b64url-decode(b64url-encode(bytes)))).to.eq(hex(bytes));
  }

  it 'has no +, /, or = characters in its output', {
    expect(b64url-encode(bytes) ~~ /<[+/=]>/).to.be-falsy;
  }
}

describe 'urlsafe-token', {
  it 'returns a different token on each call', {
    expect(urlsafe-token()).not.to.eq(urlsafe-token());
  }

  it 'returns a url-safe token', {
    expect(urlsafe-token() ~~ /^ <[A..Za..z0..9\-_]>+ $/).to.be-truthy;
  }
}

describe 'aes256-encrypt', {
  let(:key, { derive-key('a secret') });
  let(:iv, { random-bytes(16) });
  let(:plain, { 'sensitive value 🔒'.encode('utf-8') });

  it 'round-trips a value through aes256-decrypt', {
    expect(hex(aes256-decrypt(key, iv, aes256-encrypt(key, iv, plain)))).to.eq(hex(plain));
  }
}

describe 'constant-time-eq', {
  it 'is true for equal blobs', {
    expect(constant-time-eq('abc'.encode, 'abc'.encode)).to.be-truthy;
  }

  it 'is false for differing blobs', {
    expect(constant-time-eq('abc'.encode, 'abd'.encode)).to.be-falsy;
  }

  it 'is false for different lengths', {
    expect(constant-time-eq('abc'.encode, 'ab'.encode)).to.be-falsy;
  }
}
