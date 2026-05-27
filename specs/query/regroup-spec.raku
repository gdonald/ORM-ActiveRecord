use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class RgUser is Model {
  method table-name { 'users' }
}

describe 'regroup', {
  before-each {
    RgUser.destroy-all;
    RgUser.create({fname => 'Alice', lname => 'Anderson'});
    RgUser.create({fname => 'Adam',  lname => 'Anderson'});
    RgUser.create({fname => 'Bob',   lname => 'Brown'});
    RgUser.create({fname => 'Carol', lname => 'Carter'});
  }

  after-each {
    RgUser.destroy-all;
  }

  context 'regroup replaces an existing group', {
    it 'collapses to 3 lname groups', {
      my @lnames = RgUser.group('fname').regroup('lname').pluck('lname').sort;

      expect(@lnames.elems).to.eq(3);
    }

    it 'picked the right column', {
      my @lnames = RgUser.group('fname').regroup('lname').pluck('lname').sort;

      expect(@lnames.join(',')).to.eq('Anderson,Brown,Carter');
    }
  }

  it 'acts as group when no prior group', {
    expect(RgUser.regroup('lname').count.elems).to.eq(3);
  }

  it 'with multiple columns replaces in full', {
    my @rows = RgUser.group('lname').regroup('lname', 'fname').pluck('lname', 'fname');

    expect(@rows.elems).to.eq(4);
  }

  it 'group-values reflects the replacement', {
    expect(RgUser.group('fname').regroup('lname').group-values.join(',')).to.eq('lname');
  }
}
