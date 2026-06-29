use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Magazine;
use Models::Subscription;
use Models::Profile;
use Models::Account;

%*ENV<DISABLE-SQL-LOG> = True;

sub tel-seed {
  clean-shared-tables;

  my %h;
  %h<alice> = User.create({fname => 'Alice', lname => 'A'});
  %h<bob>   = User.create({fname => 'Bob',   lname => 'B'});
  %h<carol> = User.create({fname => 'Carol', lname => 'C'});

  %h<mag-a> = Magazine.create({title => 'Wired'});
  %h<mag-b> = Magazine.create({title => 'Time'});
  %h<mag-c> = Magazine.create({title => 'Vogue'});

  Subscription.create({user => %h<alice>, magazine => %h<mag-a>});
  Subscription.create({user => %h<alice>, magazine => %h<mag-b>});
  Subscription.create({user => %h<bob>,   magazine => %h<mag-a>});
  Subscription.create({user => %h<bob>,   magazine => %h<mag-c>});

  %h<acct-a> = Account.create({name => 'alice-acct'});
  %h<acct-b> = Account.create({name => 'bob-acct'});
  Profile.create({user => %h<alice>, account => %h<acct-a>, bio => 'A bio'});
  Profile.create({user => %h<bob>,   account => %h<acct-b>, bio => 'B bio'});
  %h;
}

describe 'through eager loading', {
  before-each { tel-seed }
  after-each  { clean-shared-tables }

  context 'class-level eager loading without a leading where', {
    it 'includes a has-many :through directly from the class', {
      my @users = User.includes(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<magazines>:exists).to.be-truthy;
    }

    it 'preloads a has-many :through directly from the class', {
      my @users = User.preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.map(*.attrs<title>).sort.join(',')).to.eq('Time,Wired');
    }

    it 'eager-loads a has-many :through directly from the class', {
      my @users = User.eager-load(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<magazines>:exists).to.be-truthy;
    }
  }

  context 'preload has-many :through caches collection', {
    it 'caches on Alice', {
      my @users = User.where({}).preload(:magazines).all;
      my $u = @users.first({ .attrs<fname> eq 'Alice' });
      expect($u.assoc-cache<magazines>:exists).to.be-truthy;
    }

    it 'returns correct count for Alice', {
      my @users = User.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }

    it 'returns correct rows for Alice', {
      my @users = User.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.map(*.attrs<title>).sort.join(',')).to.eq('Time,Wired');
    }

    it 'returns correct rows for Bob', {
      my @users = User.where({}).preload(:magazines).all;
      my $b = @users.first({ .attrs<fname> eq 'Bob' });
      expect($b.magazines.map(*.attrs<title>).sort.join(',')).to.eq('Vogue,Wired');
    }

    it 'returns empty for Carol', {
      my @users = User.where({}).preload(:magazines).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.magazines.elems).to.eq(0);
    }
  }

  context 'preload also stitches the join collection', {
    it 'caches the intermediate collection', {
      my @users = User.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<subscriptions>:exists).to.be-truthy;
    }

    it 'cached intermediate has right count', {
      my @users = User.where({}).preload(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.subscriptions.elems).to.eq(2);
    }
  }

  context 'preload has-one :through caches singular', {
    it 'caches the account', {
      my @users = User.where({}).preload(:account).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<account>:exists).to.be-truthy;
    }

    it 'returns the correct account', {
      my @users = User.where({}).preload(:account).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.account.attrs<name>).to.eq('alice-acct');
    }

    it 'caches even when no join row', {
      my @users = User.where({}).preload(:account).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.assoc-cache<account>:exists).to.be-truthy;
    }

    it 'returns Nil when no join row', {
      my @users = User.where({}).preload(:account).all;
      my $c = @users.first({ .attrs<fname> eq 'Carol' });
      expect($c.account.defined).to.be-falsy;
    }
  }

  context 'eager-load on has-many :through', {
    it 'caches on Alice', {
      my @users = User.where({}).eager-load(:magazines).all;
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
      my @users = User.where({}).eager-load(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }
  }

  context 'includes(:through) without references', {
    it 'caches via preload path', {
      my @users = User.where({}).includes(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.assoc-cache<magazines>:exists).to.be-truthy;
    }

    it 'returns the right collection', {
      my @users = User.where({}).includes(:magazines).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      expect($a.magazines.elems).to.eq(2);
    }
  }

  context 'nested preload: through -> further association', {
    it 'caches grandchild', {
      my @users = User.where({}).preload(magazines => :subscriptions).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      my $mag = $a.magazines.first({ .attrs<title> eq 'Wired' });
      expect($mag.assoc-cache<subscriptions>:exists).to.be-truthy;
    }

    it 'resolves grandchild rows', {
      my @users = User.where({}).preload(magazines => :subscriptions).all;
      my $a = @users.first({ .attrs<fname> eq 'Alice' });
      my $mag = $a.magazines.first({ .attrs<title> eq 'Wired' });
      expect($mag.subscriptions.elems).to.be-greater-than(0);
    }
  }
}
