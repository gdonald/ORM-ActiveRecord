use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'regroup', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Adam',  lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
    User.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    User.destroy-all;
  }

  context 'regroup replaces an existing group', {
    it 'collapses to 3 lname groups', {
      my @lnames = User.group('fname').regroup('lname').pluck('lname').sort;

      expect(@lnames.elems).to.eq(3);
    }

    it 'picked the right column', {
      my @lnames = User.group('fname').regroup('lname').pluck('lname').sort;

      expect(@lnames.join(',')).to.eq('Anderson,Brown,Carter');
    }
  }

  it 'acts as group when no prior group', {
    expect(User.regroup('lname').count.elems).to.eq(3);
  }

  it 'with multiple columns replaces in full', {
    my @rows = User.group('lname').regroup('lname', 'fname').pluck('lname', 'fname');

    expect(@rows.elems).to.eq(4);
  }

  it 'group-values reflects the replacement', {
    expect(User.group('fname').regroup('lname').group-values.join(',')).to.eq('lname');
  }
}
