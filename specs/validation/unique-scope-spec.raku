use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::UniqueScope;

%*ENV<DISABLE-SQL-LOG> = True;

sub clean {
  Subscription.destroy-all;
  Magazine.destroy-all;
  User.destroy-all;
}

describe 'uniqueness with scope', {
  before-each { clean }
  after-each  { clean }

  context 'first subscription for a (user, magazine) pair', {
    it 'is valid', {
      my $user     = User.create({fname => 'Greg'});
      my $magazine = Magazine.create({title => 'Mad'});
      my $sub      = Subscription.create({:$user, :$magazine});
      expect($sub.is-valid).to.be-truthy;
    }
  }

  context 'second subscription for the same pair', {
    it 'is invalid', {
      my $user     = User.create({fname => 'Greg'});
      my $magazine = Magazine.create({title => 'Mad'});
      Subscription.create({:$user, :$magazine});
      my $sub      = Subscription.build({:$user, :$magazine});
      expect($sub.is-valid).to.be-falsy;
    }

    it 'reports "must be unique" on user_id', {
      my $user     = User.create({fname => 'Greg'});
      my $magazine = Magazine.create({title => 'Mad'});
      Subscription.create({:$user, :$magazine});
      my $sub      = Subscription.build({:$user, :$magazine});
      $sub.is-valid;
      expect($sub.errors.user_id[0]).to.eq('must be unique');
    }
  }
}
