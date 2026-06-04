use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::Environment;

%*ENV<DISABLE-SQL-LOG> = True;

# current-env defaults to 'test' under behave (BEHAVE_WORKER_COUNT set); clear it
# so the caller-default tests below are deterministic.
%*ENV<BEHAVE_WORKER_COUNT>:delete;

describe 'current-env', {
  it 'returns the caller default when AR_ENV is unset (outside behave)', {
    temp %*ENV<AR_ENV>;
    %*ENV<AR_ENV>:delete;
    temp %*ENV<BEHAVE_WORKER_COUNT>;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    expect(current-env('development')).to.eq('development');
  }

  it 'defaults to test under behave (BEHAVE_WORKER_COUNT set)', {
    temp %*ENV<AR_ENV>;
    %*ENV<AR_ENV>:delete;
    temp %*ENV<BEHAVE_WORKER_COUNT> = '4';

    expect(current-env('development')).to.eq('test');
  }

  it 'returns AR_ENV when set', {
    temp %*ENV<AR_ENV> = 'production';

    expect(current-env('development')).to.eq('production');
  }

  it 'ignores an empty AR_ENV', {
    temp %*ENV<AR_ENV> = '';
    temp %*ENV<BEHAVE_WORKER_COUNT>;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    expect(current-env('development')).to.eq('development');
  }

  it 'returns RAKU_ENV when AR_ENV is unset', {
    temp %*ENV<AR_ENV>;
    %*ENV<AR_ENV>:delete;
    temp %*ENV<RAKU_ENV> = 'production';
    temp %*ENV<BEHAVE_WORKER_COUNT>;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    expect(current-env('development')).to.eq('production');
  }

  it 'lets AR_ENV win over RAKU_ENV', {
    temp %*ENV<AR_ENV>  = 'staging';
    temp %*ENV<RAKU_ENV> = 'production';

    expect(current-env('development')).to.eq('staging');
  }

  it 'ignores an empty RAKU_ENV', {
    temp %*ENV<AR_ENV>;
    %*ENV<AR_ENV>:delete;
    temp %*ENV<RAKU_ENV> = '';
    temp %*ENV<BEHAVE_WORKER_COUNT>;
    %*ENV<BEHAVE_WORKER_COUNT>:delete;

    expect(current-env('development')).to.eq('development');
  }
}

describe 'default-connection', {
  it 'is primary', {
    expect(default-connection()).to.eq('primary');
  }
}
