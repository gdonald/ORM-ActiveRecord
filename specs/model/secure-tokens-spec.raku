use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Model;
use ORM::ActiveRecord::Support::Secrets;

%*ENV<DISABLE-SQL-LOG> = True;
secret-key-base('test-secret-key-base-12345');

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

if $has-db {
  $adapter.exec('DROP TABLE IF EXISTS _secure_users');
  $adapter.ddl-create-table('_secure_users', [
    email           => { :string, limit => 120 },
    auth_token      => { :string, limit => 64 },
    password_digest => { :string, limit => 255 },
  ]);
}

class SecureUser is Model {
  method table-name { '_secure_users' }

  submethod BUILD {
    self.has-secure-token('auth_token');
    self.has-secure-password(:iterations(1000));
    self.generates-token-for('password-reset', :expires-in(900), { .password_digest // '' });
  }
}

GLOBAL::<SecureUser> := SecureUser;

END { try $adapter.exec('DROP TABLE IF EXISTS _secure_users') if $has-db }

describe 'secure-token helper', {
  it 'returns a url-safe token', {
    expect(SecureUser.secure-token ~~ /^ <[A..Za..z0..9\-_]>+ $/).to.be-truthy;
  }
}

my &group = $has-db ?? &describe !! &xdescribe;

group 'secure tokens, passwords, and signed ids', :order<defined>, {
  before-each { SecureUser.destroy-all }
  after-each  { SecureUser.destroy-all }

  context 'has-secure-token', :order<defined>, {
    it 'generates a token on create', {
      expect(SecureUser.create({ email => 'a@x.com' }).auth_token.chars).to.be-greater-than(19);
    }

    it 'persists the generated token', {
      my $u = SecureUser.create({ email => 'a@x.com' });
      expect(SecureUser.find($u.id).auth_token).to.eq($u.auth_token);
    }

    it 'keeps a supplied token', {
      expect(SecureUser.create({ email => 'b@x.com', auth_token => 'fixed' }).auth_token).to.eq('fixed');
    }

    it 'regenerates and persists a new token', {
      my $u = SecureUser.create({ email => 'a@x.com' });
      my $old = $u.auth_token;
      $u.regenerate-secure-token('auth_token');
      expect(SecureUser.find($u.id).auth_token).not.to.eq($old);
    }
  }

  context 'has-secure-password', :order<defined>, {
    it 'stores the password as a pbkdf2 digest', {
      my $u = SecureUser.create({ email => 'c@x.com', password => 'correct horse' });
      expect(($u.attrs<password_digest> // '').starts-with('pbkdf2-sha256$')).to.be-truthy;
    }

    it 'authenticates with the right password', {
      my $u = SecureUser.create({ email => 'c@x.com', password => 'correct horse' });
      expect(SecureUser.find($u.id).authenticate('correct horse')).to.be-truthy;
    }

    it 'rejects the wrong password', {
      my $u = SecureUser.create({ email => 'c@x.com', password => 'correct horse' });
      expect(SecureUser.find($u.id).authenticate('nope')).to.be-falsy;
    }
  }

  context 'signed-id', :order<defined>, {
    it 'round-trips with a matching purpose', {
      my $u = SecureUser.create({ email => 'd@x.com' });
      expect(SecureUser.find-signed($u.signed-id(:purpose('unsubscribe')), :purpose('unsubscribe')).id).to.eq($u.id);
    }

    it 'rejects a wrong purpose', {
      my $u = SecureUser.create({ email => 'd@x.com' });
      expect(SecureUser.find-signed($u.signed-id(:purpose('unsubscribe')), :purpose('other'))).to.be-falsy;
    }

    it 'rejects a tampered token', {
      my $u = SecureUser.create({ email => 'd@x.com' });
      expect(SecureUser.find-signed($u.signed-id(:purpose('unsubscribe')) ~ 'x', :purpose('unsubscribe'))).to.be-falsy;
    }

    it 'rejects an expired token', {
      my $u = SecureUser.create({ email => 'd@x.com' });
      expect(SecureUser.find-signed($u.signed-id(:purpose('unsubscribe'), :expires-in(-10)), :purpose('unsubscribe'))).to.be-falsy;
    }

    it 'throws from find-signed-or-die on an invalid token', {
      expect({ SecureUser.find-signed-or-die('nope', :purpose('unsubscribe')) }).to.raise-error;
    }
  }

  context 'generates-token-for', :order<defined>, {
    it 'finds the record by a fresh token', {
      my $u = SecureUser.create({ email => 'e@x.com', password => 'first' });
      expect(SecureUser.find-by-token-for('password-reset', $u.generate-token-for('password-reset')).id).to.eq($u.id);
    }

    it 'invalidates the token once the embedded value changes', {
      my $u = SecureUser.create({ email => 'e@x.com', password => 'first' });
      my $token = $u.generate-token-for('password-reset');
      $u.password = 'second';
      $u.save;
      expect(SecureUser.find-by-token-for('password-reset', $token)).to.be-falsy;
    }
  }
}
