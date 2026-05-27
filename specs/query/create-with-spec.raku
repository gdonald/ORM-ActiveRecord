use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class CwUser is Model {
  method table-name { 'users' }
}

describe 'create-with', {
  before-each {
    CwUser.destroy-all;
  }

  after-each {
    CwUser.destroy-all;
  }

  it 'stores defaults on the relation', {
    my $rel = CwUser.create-with({lname => 'CW'});

    expect($rel.create-with-attrs<lname>).to.eq('CW');
  }

  context 'defaults flow into find-or-create-by', {
    it 'applies defaults when creating', {
      my $u1 = CwUser.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});

      expect($u1.defined && $u1.fname eq 'Greg' && $u1.lname eq 'CW').to.be-truthy;
    }

    it 'second find-or-create-by hits the existing row', {
      my $u1 = CwUser.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});
      my $u2 = CwUser.create-with({lname => 'Other'}).find-or-create-by({fname => 'Greg'});

      expect($u2.id).to.eq($u1.id);
    }

    it 'found row keeps its original lname; defaults do not overwrite', {
      CwUser.create-with({lname => 'CW'}).find-or-create-by({fname => 'Greg'});
      my $u2 = CwUser.create-with({lname => 'Other'}).find-or-create-by({fname => 'Greg'});

      expect($u2.lname).to.eq('CW');
    }
  }

  it 'create-with wins over where conditions for defaults', {
    my $u3 = CwUser.where({lname => 'Whoa'}).create-with({lname => 'Defaulted'})
                 .find-or-initialize-by({fname => 'Solo'});

    expect($u3.lname).to.eq('Defaulted');
  }

  it 'find params override create-with', {
    my $u4 = CwUser.create-with({fname => 'OverrideMe', lname => 'L'})
                 .find-or-create-by({fname => 'Real-Name'});

    expect($u4.fname).to.eq('Real-Name');
  }
}
