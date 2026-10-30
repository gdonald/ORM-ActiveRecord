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

  context 'updating a saved subscription', {
    let(:greg,    { User.create({fname => 'Greg'}) });
    let(:alice,   { User.create({fname => 'Alice'}) });
    let(:mad,     { Magazine.create({title => 'Mad'}) });
    let(:cracked, { Magazine.create({title => 'Cracked'}) });

    context 'to a user another subscription to the same magazine has', {
      let(:subscription, {
        Subscription.create({user => greg, magazine => mad});
        Subscription.create({user => alice, magazine => mad});
      });

      it 'is refused', {
        expect(subscription.update({user_id => greg.id})).to.be-falsy;
      }

      it 'records a taken error', {
        subscription.update({user_id => greg.id});
        expect(subscription.errors.is-of-kind('user_id', 'taken')).to.be-truthy;
      }
    }

    context 'keeping its own user', {
      let(:subscription, { Subscription.create({user => greg, magazine => mad}) });

      it 'is accepted', {
        expect(subscription.update({user_id => greg.id})).to.be-truthy;
      }
    }

    context 'to a user a subscription to another magazine has', {
      let(:subscription, {
        Subscription.create({user => greg, magazine => cracked});
        Subscription.create({user => alice, magazine => mad});
      });

      it 'is accepted', {
        expect(subscription.update({user_id => greg.id})).to.be-truthy;
      }
    }

    context 'changing another column while its user stays unique', {
      let(:subscription, { Subscription.create({user => greg, magazine => mad}) });

      it 'is accepted', {
        expect(subscription.update({magazine_id => cracked.id})).to.be-truthy;
      }
    }
  }
}
