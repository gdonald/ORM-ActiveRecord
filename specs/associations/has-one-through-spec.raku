use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class HotProfile {...}
class HotAccount {...}

class HotUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-one: profile => %(class => HotProfile, foreign-key => 'user_id');
    self.has-one: account => %(through => :profile);
  }
}

class HotProfile is Model {
  method table-name { 'profiles' }
  method fkey-name  { 'profile_id' }

  submethod BUILD {
    self.belongs-to: hotuser => %(class => HotUser,    foreign-key => 'user_id');
    self.belongs-to: account => %(class => HotAccount, foreign-key => 'account_id');
  }
}

class HotAccount is Model {
  method table-name { 'accounts' }
}

describe 'has-one :through', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  context 'before the join record exists', {
    it 'saves the user', {
      my $user = HotUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.is-valid).to.be-truthy;
    }

    it 'returns Nil', {
      my $user = HotUser.create({fname => 'Greg', lname => 'Donald'});
      expect($user.account).to.be-nil;
    }
  }

  context 'with a join profile that links an account', {
    it 'saves the profile', {
      my $user = HotUser.create({fname => 'Greg', lname => 'Donald'});
      my $acct = HotAccount.create({name => 'gdonald'});
      my $prof = HotProfile.create({hotuser => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($prof.is-valid).to.be-truthy;
    }

    it 'returns the target record', {
      my $user = HotUser.create({fname => 'Greg', lname => 'Donald'});
      my $acct = HotAccount.create({name => 'gdonald'});
      HotProfile.create({hotuser => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($user.account.defined).to.be-truthy;
    }

    it 'returns the correct record', {
      my $user = HotUser.create({fname => 'Greg', lname => 'Donald'});
      my $acct = HotAccount.create({name => 'gdonald'});
      HotProfile.create({hotuser => $user, account => $acct, bio => 'Raku enthusiast'});

      expect($user.account.id).to.eq($acct.id);
    }
  }
}
