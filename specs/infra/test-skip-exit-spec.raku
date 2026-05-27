use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::TestSkip;

%*ENV<DISABLE-SQL-LOG> = True;
%*ENV<DATABASE_URL> = 'sqlite::memory:';

describe 'skip-on under a matching adapter', {
  it 'reports that the current adapter matches the skip list', {
    expect(adapter-matches(:adapter<sqlite>)).to.be-truthy;
  }

  it 'reports the configured adapter as sqlite', {
    expect(configured-adapter-name()).to.eq('sqlite');
  }

  xit 'would exit the test process when skip-on is invoked (cannot be executed inside behave because skip-on calls exit 0)', {
    skip-on(:adapter<sqlite>, :reason('demo: feature unavailable on sqlite'));

    expect(True).to.eq(False);
  }

  pending 'behave-side equivalent of skip-on is `xit` or `pending`, which prevents the body from running just as skip-on + exit prevents the rest of a Test:: file from running';
}
