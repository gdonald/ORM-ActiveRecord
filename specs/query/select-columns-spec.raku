use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'select column narrowing', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
    User.create({fname => 'Bob',   lname => 'Brown'});
  }

  context 'a model load through a column-narrowed relation', {
    let(:user, { User.select(<id fname>).where({lname => 'Anderson'}).first });

    it 'fetches a selected column', {
      expect(user.attrs<fname>).to.eq('Alice');
    }

    it 'does not fetch an unselected column', {
      expect(user.attrs<lname>.defined).to.be-falsy;
    }

    it 'leaves an unselected column untouched when the record is saved', {
      user.attrs<fname> = 'Alicia';
      user.save;

      expect(User.find(user.id).attrs<lname>).to.eq('Anderson');
    }
  }

  it 'names only the selected columns in the generated sql', {
    expect(User.select(<id fname>).to-sql.contains('lname')).to.be-falsy;
  }

  it 'loads every column when the select names only expressions', {
    expect(User.select('COUNT(*) OVER ()').where({lname => 'Brown'}).first.attrs<lname>).to.eq('Brown');
  }
}
