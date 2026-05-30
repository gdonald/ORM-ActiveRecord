use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use Models::User;
use Models::Magazine;
use Models::Subscription;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'has-many :through', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  it 'returns the joined record through the join model', {
    my $user = User.create({fname => 'Greg'});
    my $mag  = Magazine.create({title => 'Mad'});
    Subscription.create({user => $user, magazine => $mag});

    expect($user.magazines.first.id).to.eq($mag.id);
  }
}
