use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Profile;
use Models::Account;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-one :through', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'before the join record exists', {
    it 'saves the user', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'returns Nil', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      expect($user.account).to.be-nil;
    }
  }

  context 'with a join profile that links an account', {
    it 'saves the profile', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $acct = Account.create({name => 'gdonald'});
      my $prof = Profile.create({user => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($prof.is-valid).to.be-truthy;
    }

    it 'returns the target record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $acct = Account.create({name => 'gdonald'});
      Profile.create({user => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($user.account.defined).to.be-truthy;
    }

    it 'returns the correct record', {
      my $user = User.create({fname => 'Greg', lname => 'Donald'});
      my $acct = Account.create({name => 'gdonald'});
      Profile.create({user => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($user.account.id).to.eq($acct.id);
    }
  }
}
