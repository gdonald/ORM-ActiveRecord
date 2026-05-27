use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class TelSubscription {...}
class TelProfile      {...}
class TelAccount      {...}

class TelUser is Model {
  method table-name { 'users' }
  method fkey-name  { 'user_id' }

  submethod BUILD {
    self.has-many: subscriptions => %(class => TelSubscription, foreign-key => 'user_id');
    self.has-many: magazines     => %(through => :subscriptions);
    self.has-one:  profile       => %(class => TelProfile, foreign-key => 'user_id');
    self.has-one:  account       => %(through => :profile);
  }
}

class TelMagazine is Model {
  method table-name { 'magazines' }
  method fkey-name  { 'magazine_id' }

  submethod BUILD {
    self.has-many: subscriptions => %(class => TelSubscription, foreign-key => 'magazine_id');
  }
}

class TelSubscription is Model {
  method table-name { 'subscriptions' }

  submethod BUILD {
    self.belongs-to: teluser  => %(class => TelUser,     foreign-key => 'user_id');
    self.belongs-to: magazine => %(class => TelMagazine, foreign-key => 'magazine_id');
  }
}

class TelProfile is Model {
  method table-name { 'profiles' }

  submethod BUILD {
    self.belongs-to: teluser => %(class => TelUser,    foreign-key => 'user_id');
    self.belongs-to: account => %(class => TelAccount, foreign-key => 'account_id');
  }
}

class TelAccount is Model {
  method table-name { 'accounts' }
}

sub tel-seed {
  clean-shared-tables;

  my %h;
  %h<alice> = TelUser.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = TelUser.create({fname => 'Bob',   lname => 'B'});
  %h<carol> = TelUser.create({fname => 'Carol', lname => 'C'});

  %h<mag-a> = TelMagazine.create({title => 'Wired'});
  %h<mag-b> = TelMagazine.create({title => 'Time'});
  %h<mag-c> = TelMagazine.create({title => 'Vogue'});

  TelSubscription.create({teluser => %h<alice>, magazine => %h<mag-a>});
  TelSubscription.create({teluser => %h<alice>, magazine => %h<mag-b>});
  TelSubscription.create({teluser => %h<bob>,   magazine => %h<mag-a>});
  TelSubscription.create({teluser => %h<bob>,   magazine => %h<mag-c>});

  %h<acct-a> = TelAccount.create({name => 'alice-acct'});
  %h<acct-b> = TelAccount.create({name => 'bob-acct'});
  TelProfile.create({teluser => %h<alice>, account => %h<acct-a>, bio => 'A bio'});
  TelProfile.create({teluser => %h<bob>,   account => %h<acct-b>, bio => 'B bio'});
  %h;
}

sub tel-clean {
  clean-shared-tables;
}

describe 'through eager loading', {
  before-each { tel-seed }
  after-each  { tel-clean }

  context 'preload has-many :through caches collection', {
    it 'caches on Alice', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $u = @users.first({ .attrs<fname> eq 'Alice' });
      expect($u.assoc-cache<magazines>:exists).to.be-truthy;
    }

    it 'returns correct count for Alice', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }

    it 'returns correct rows for Alice', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.map(*.attrs<title>).sort.join(',')).to.eq('Time,Wired');
    }

    it 'returns correct rows for Bob', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $b = @users.first({ .attrs<fname> eq 'Bob' });
      expect($b.magazines.map(*.attrs<title>).sort.join(',')).to.eq('Vogue,Wired');
    }

    it 'returns empty for Carol', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.magazines.elems).to.eq(0);
    }
  }

  context 'preload also stitches the join collection', {
    it 'caches the intermediate collection', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<subscriptions>:exists).to.be-truthy;
    }

    it 'cached intermediate has right count', {
      my @users = TelUser.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.subscriptions.elems).to.eq(2);
    }
  }

  context 'preload has-one :through caches singular', {
    it 'caches the account', {
      my @users = TelUser.where({}).preload(:account).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<account>:exists).to.be-truthy;
    }

    it 'returns the correct account', {
      my @users = TelUser.where({}).preload(:account).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.account.attrs<name>).to.eq('alice-acct');
    }

    it 'caches even when no join row', {
      my @users = TelUser.where({}).preload(:account).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.assoc-cache<account>:exists).to.be-truthy;
    }

    it 'returns Nil when no join row', {
      my @users = TelUser.where({}).preload(:account).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.account.defined).to.be-falsy;
    }
  }

  context 'eager-load on has-many :through', {
    it 'caches on Alice', {
      my @users = TelUser.where({}).eager-load(:magazines).all;
      my %seen;
      my $cached = False;
      for @users -> $u {
        next if %seen{$u.attrs<fname>}:exists;
        %seen{$u.attrs<fname>} = True;
        $cached = True if $u.attrs<fname> eq 'Alice' && ($u.assoc-cache<magazines>:exists);
      }
      expect($cached).to.be-truthy;
    }

    it 'returns correct count for Alice', {
      my @users = TelUser.where({}).eager-load(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }
  }

  context 'includes(:through) without references', {
    it 'caches via preload path', {
      my @users = TelUser.where({}).includes(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<magazines>:exists).to.be-truthy;
    }

    it 'returns the right collection', {
      my @users = TelUser.where({}).includes(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }
  }

  context 'nested preload: through -> further association', {
    it 'caches grandchild', {
      my @users = TelUser.where({}).preload(magazines => :subscriptions).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      my $mag = $a.magazines.first({ .attrs<title> eq 'Wired' });
      expect($mag.assoc-cache<subscriptions>:exists).to.be-truthy;
    }

    it 'resolves grandchild rows', {
      my @users = TelUser.where({}).preload(magazines => :subscriptions).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      my $mag = $a.magazines.first({ .attrs<title> eq 'Wired' });
      expect($mag.subscriptions.elems).to.be-greater-than(0);
    }
  }
}
