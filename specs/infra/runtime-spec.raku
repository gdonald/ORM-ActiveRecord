use lib 'lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::Runtime;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'runtime tasks', {
  my $runtime = Runtime.new;

  context 'runner', {
    it 'evaluates inline code', {
      expect($runtime.run-code('6 * 7')).to.eq(42);
    }

    it 'evaluates a script file', {
      my $script = $*TMPDIR.add("runner-spec-{$*PID}-{(now * 1e6).Int}.raku").Str;
      $script.IO.spurt("21 + 21\n");
      LEAVE { $script.IO.unlink if $script.IO.e }

      expect($runtime.run-script($script)).to.eq(42);
    }
  }

  context 'console', {
    let(:command, { $runtime.console-command(includes => <lib app/models>) });

    it 'launches raku', {
      expect(command[0]).to.eq('raku');
    }

    it 'puts the include paths on the command line', {
      aggregate-failures {
        expect(command.grep({ $_ eq '-Ilib' }).elems).to.be-truthy;
        expect(command.grep({ $_ eq '-Iapp/models' }).elems).to.be-truthy;
      }
    }
  }

  context 'dbconsole', {
    it 'builds the sqlite3 invocation', {
      my %command = $runtime.client-command({ adapter => 'sqlite', name => 'db/dev.sqlite3' });
      expect(%command<argv>).to.eq(['sqlite3', 'db/dev.sqlite3']);
    }

    it 'builds the psql invocation and passes the password', {
      my %command = $runtime.client-command({
        adapter => 'pg', host => 'db.example', port => 5433,
        user => 'app', password => 'secret', name => 'app_dev',
      });

      aggregate-failures {
        expect(%command<argv>[0]).to.eq('psql');
        expect(%command<env><PGPASSWORD>).to.eq('secret');
      }
    }

    it 'builds the mysql invocation', {
      my %command = $runtime.client-command({ adapter => 'mysql', user => 'root', name => 'app_dev' });
      expect(%command<argv>[0]).to.eq('mysql');
    }
  }

  context 'notes', {
    it 'finds annotations across source files', {
      my $dir = $*TMPDIR.add("notes-spec-{$*PID}-{(now * 1e6).Int}");
      $dir.mkdir;
      LEAVE { run 'rm', '-rf', $dir.Str }

      $dir.add('a.rakumod').spurt: qq:to/SRC/;
      # TODO: wire this up
      my \$x = 1;  # FIXME later
      SRC

      my @notes = $runtime.scan-notes([$dir.Str]);

      aggregate-failures {
        expect(@notes.elems).to.eq(2);
        expect(@notes.first({ .<tag> eq 'TODO' })<text>).to.eq('wire this up');
      }
    }
  }

  context 'stats', {
    it 'counts models and migrations', {
      my $code = $*TMPDIR.add("stats-spec-{$*PID}-{(now * 1e6).Int}");
      my $mig  = $*TMPDIR.add("stats-spec-mig-{$*PID}-{(now * 1e6).Int}");
      $code.mkdir;
      $mig.mkdir;
      LEAVE { run 'rm', '-rf', $code.Str; run 'rm', '-rf', $mig.Str }

      $code.add('user.rakumod').spurt("class User is Model \{\n\}\n");
      $mig.add('001-create-users.raku').spurt('');
      $mig.add('002-create-pets.raku').spurt('');

      my %stats = $runtime.compute-stats(code-dirs => [$code.Str], migrate-dir => $mig.Str);

      aggregate-failures {
        expect(%stats<models>).to.eq(1);
        expect(%stats<migrations>).to.eq(2);
      }
    }
  }
}
