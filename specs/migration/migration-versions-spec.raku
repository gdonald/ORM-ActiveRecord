use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Errors::X;
use ORM::ActiveRecord::Schema::Migrate;

%*ENV<DISABLE-SQL-LOG> = True;

sub write-empty-migration(IO::Path:D $dir, Str:D $file, Str:D $class) {
  $dir.add($file).spurt(qq:to/RAKU/);
    use ORM::ActiveRecord::Schema::Migration;

    class $class is Migration \{
      method up \{ \}
      method down \{ \}
    \}
    RAKU
}

describe 'migration versions', {
  context 'with two files that share a version', {
    let(:dir, {
      my $tmp = $*TMPDIR.add('ar-migration-duplicates-spec-' ~ $*PID);
      $tmp.mkdir;
      $tmp;
    });

    let(:migrate, { Migrate.new(:migration-path(dir.Str)) });

    it 'throws instead of skipping one of them', {
      write-empty-migration(dir, '19000101000001-create-forms.raku', 'SpecCreateForms');
      write-empty-migration(dir, '19000101000001-create-form_fields.raku', 'SpecCreateFormFields');

      expect({ migrate.migrate(['up', 0]) }).to.raise-error(X::DuplicateMigrationVersion);

      run 'rm', '-rf', dir.Str;
    }
  }

  context 'with a file added below the highest applied version', {
    let(:dir, {
      my $tmp = $*TMPDIR.add('ar-migration-out-of-order-spec-' ~ $*PID);
      $tmp.mkdir;
      $tmp;
    });

    let(:migrate, { Migrate.new(:migration-path(dir.Str)) });

    it 'runs the added file', {
      migrate.check-migrations-table;

      write-empty-migration(dir, '19000101000003-create-reports.raku', 'SpecCreateReports');
      migrate.migrate(['up', 0]);

      write-empty-migration(dir, '19000101000002-create-report_rows.raku', 'SpecCreateReportRows');
      migrate.migrate(['up', 0]);

      my @applied = migrate.applied-versions;

      migrate.migrate(['down', 0]);
      run 'rm', '-rf', dir.Str;

      expect('19000101000002' (elem) @applied).to.be-truthy;
    }
  }
}
