use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-many :through with source and disable-joins', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'baseline has-many through resolves', {
    my $user = User.create({fname => 'Greg'});
    my $mag-a = Magazine.create({title => 'A'});
    my $mag-b = Magazine.create({title => 'B'});
    Subscription.create({user => $user, magazine => $mag-a});
    Subscription.create({user => $user, magazine => $mag-b});

    expect($user.subscriptions.map({ $_.attrs<magazine_id> }).sort.elems).to.eq(2);
  }

  context 'source: alias', {
    it 'resolves through-target', {
      my $user = User.create({fname => 'Greg'});
      my $mag-a = Magazine.create({title => 'A'});
      my $mag-b = Magazine.create({title => 'B'});
      Subscription.create({user => $user, magazine => $mag-a});
      Subscription.create({user => $user, magazine => $mag-b});

      expect($user.subscribed-mags.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = User.create({fname => 'Greg'});
      my $mag-a = Magazine.create({title => 'A'});
      my $mag-b = Magazine.create({title => 'B'});
      Subscription.create({user => $user, magazine => $mag-a});
      Subscription.create({user => $user, magazine => $mag-b});

      expect($user.subscribed-mags.map({ $_.attrs<title> }).sort.join(',')).to.eq('A,B');
    }
  }

  context 'disable-joins', {
    it 'returns the correct number of rows', {
      my $user = User.create({fname => 'Greg'});
      my $mag-a = Magazine.create({title => 'A'});
      my $mag-b = Magazine.create({title => 'B'});
      Subscription.create({user => $user, magazine => $mag-a});
      Subscription.create({user => $user, magazine => $mag-b});

      expect($user.dj-mags.elems).to.eq(2);
    }

    it 'returns the right rows', {
      my $user = User.create({fname => 'Greg'});
      my $mag-a = Magazine.create({title => 'A'});
      my $mag-b = Magazine.create({title => 'B'});
      Subscription.create({user => $user, magazine => $mag-a});
      Subscription.create({user => $user, magazine => $mag-b});

      expect($user.dj-mags.map({ $_.attrs<title> }).sort.join(',')).to.eq('A,B');
    }

    it 'returns an empty list when there are no through-rows', {
      my $lonely = User.create({fname => 'Lonely'});
      expect($lonely.dj-mags.elems).to.eq(0);
    }
  }
}
