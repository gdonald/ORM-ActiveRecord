use lib 'lib';
use BDD::Behave;
use lib 'specs/lib';
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;


describe 'references', {
  before-each {
    User.destroy-all;
    User.create({fname => 'Alice', lname => 'Anderson'});
  }

  after-each {
    User.destroy-all;
  }

  it 'is empty by default', {
    expect(User.all.references-values.elems).to.eq(0);
  }

  it 'stores a single association name', {
    expect(User.references('posts').references-values.join(',')).to.eq('posts');
  }

  it 'stores multiple association names', {
    expect(User.references('posts', 'comments').references-values.join(',')).to.eq('posts,comments');
  }

  it 'multiple references calls accumulate', {
    expect(User.references('posts').references('comments').references-values.join(',')).to.eq('posts,comments');
  }

  it 'does not alter row counts', {
    expect(User.references('posts').count).to.eq(1);
  }

  it 'merge appends references', {
    expect(User.references('posts').merge(User.references('comments')).references-values.join(',')).to.eq('posts,comments');
  }

  it 'unscope(:references) clears them', {
    expect(User.references('posts').unscope(:references).references-values.elems).to.eq(0);
  }
}
