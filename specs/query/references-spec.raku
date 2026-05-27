use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Model;

%*ENV<DISABLE-SQL-LOG> = True;

class RfUser is Model {
  method table-name { 'users' }
}

describe 'references', {
  before-each {
    RfUser.destroy-all;
    RfUser.create({fname => 'Alice', lname => 'Anderson'});
  }

  after-each {
    RfUser.destroy-all;
  }

  it 'is empty by default', {
    expect(RfUser.all.references-values.elems).to.eq(0);
  }

  it 'stores a single association name', {
    expect(RfUser.references('posts').references-values.join(',')).to.eq('posts');
  }

  it 'stores multiple association names', {
    expect(RfUser.references('posts', 'comments').references-values.join(',')).to.eq('posts,comments');
  }

  it 'multiple references calls accumulate', {
    expect(RfUser.references('posts').references('comments').references-values.join(',')).to.eq('posts,comments');
  }

  it 'does not alter row counts', {
    expect(RfUser.references('posts').count).to.eq(1);
  }

  it 'merge appends references', {
    expect(RfUser.references('posts').merge(RfUser.references('comments')).references-values.join(',')).to.eq('posts,comments');
  }

  it 'unscope(:references) clears them', {
    expect(RfUser.references('posts').unscope(:references).references-values.elems).to.eq(0);
  }
}
