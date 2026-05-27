use lib 'lib';
use BDD::Behave;

my $src = 'lib/ORM/ActiveRecord/Support/Log.rakumod'.IO.slurp;
my $bin = 'bin/ar'.IO.slurp;

describe 'Support::Log source', {
  it 'does not unconditionally open log/error.log', {
    expect($src).not.to.match(/"send-to('log/error.log'"/);
  }

  it 'honors the ORM_LOG_FILE environment variable', {
    expect($src).to.match(/ORM_LOG_FILE/);
  }
}

describe 'Support::Log loading', {
  it 'loads cleanly when ORM_LOG_FILE is unset', {
    %*ENV<ORM_LOG_FILE>:delete;

    expect({
      require ORM::ActiveRecord::Support::Log;
    }).not.to.raise-error;
  }

  it 'does not create a log/ directory in CWD', {
    expect('log'.IO.d.not || !('log'.IO.add('was-just-created').e)).to.be-truthy;
  }

  it 'loads cleanly when ORM_LOG_FILE is set', {
    my $tmp = $*TMPDIR.add("orm-ar-log-{$*PID}.log");
    $tmp.unlink if $tmp.e;
    %*ENV<ORM_LOG_FILE> = $tmp.Str;

    expect({
      require ORM::ActiveRecord::Support::Log;
    }).not.to.raise-error;

    $tmp.unlink if $tmp.e;
  }
}

describe 'bin/ar', {
  it 'defaults ORM_LOG_FILE to log/error.log only when log/ exists', {
    expect($bin).to.match(/'BEGIN' \s+ '%*ENV<ORM_LOG_FILE>' \s* '//=' .* "'log'.IO.d"/);
  }
}
