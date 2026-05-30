use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'create-with', {
  before-each {
    User.destroy-all;
  }

  after-each {
    User.destroy-all;
  }

  it 'stores defaults on the relation', {
    my $rel = User.create-with({lname => 'CW'});

    expect($rel.create-with-attrs<lname>).to.eq('CW');
  }

  context 'defaults flow into find-or-create-by', {
    it 'applies defaults when creating', {
      my $u1 = User.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});

      expect($u1.defined && $u1.fname eq 'Greg' && $u1.lname eq 'CW').to.be-truthy;
    }

    it 'second find-or-create-by hits the existing row', {
      my $u1 = User.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});
      my $u2 = User.create-with({lname => 'Other'}).find-or-create-by({fname => 'Greg'});

      expect($u2.id).to.eq($u1.id);
    }

    it 'found row keeps its original lname; defaults do not overwrite', {
      User.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});
      my $u2 = User.create-with({lname => 'Other'}).find-or-create-by({fname => 'Greg'});

      expect($u2.lname).to.eq('CW');
    }
  }

  it 'create-with wins over where conditions for defaults', {
    my $u3 = User.where({lname => 'Whoa'}).create-with({lname => 'Defaulted'})
                 .find-or-initialize-by({fname => 'Solo'});

    expect($u3.lname).to.eq('Defaulted');
  }

  it 'find params override create-with', {
    my $u4 = User.create-with({fname => 'OverrideMe', lname => 'L'})
                 .find-or-create-by({fname => 'Real-Name'});

    expect($u4.fname).to.eq('Real-Name');
  }
}
