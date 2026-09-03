use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use SpecHelpers;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Instrumentation::Notifications;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'an UPDATE from save', {
  before-each { clean-shared-tables }
  after-each  { clean-shared-tables }

  let(:sql-of, {
    -> &block {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });
      block();
      Notifications.unsubscribe($sub);
      @sql;
    }
  });

  let(:updates-of, {
    -> &block { sql-of()(&block).grep({ .uc.contains('UPDATE') }) }
  });

  let(:saved, { User.create({fname => 'Greg', lname => 'Donald'}) });

  it 'names a column that changed', {
    saved.attrs<fname> = 'Ann';

    expect(updates-of()(-> { saved.save })[0].contains('fname')).to.be-truthy;
  }

  it 'leaves out a column that did not change', {
    saved.attrs<fname> = 'Ann';

    expect(updates-of()(-> { saved.save })[0].contains('lname')).to.be-falsy;
  }

  it 'issues no statement when nothing changed', {
    saved;

    expect(updates-of()(-> { saved.save }).elems).to.eq(0);
  }

  it 'still reports the save as successful when nothing changed', {
    saved;

    expect(saved.save).to.be-truthy;
  }

  it 'writes the new value', {
    saved.attrs<fname> = 'Ann';
    saved.save;

    expect(User.find(saved.id).attrs<fname>).to.eq('Ann');
  }

  it 'leaves a column another writer changed in the meantime alone', {
    my $first  = User.find(saved.id);
    my $second = User.find(saved.id);

    $first.attrs<fname> = 'Ann';
    $first.save;

    $second.attrs<lname> = 'Smith';
    $second.save;

    expect(User.find(saved.id).attrs<fname>).to.eq('Ann');
  }

  it 'writes the column the second writer changed', {
    my $first  = User.find(saved.id);
    my $second = User.find(saved.id);

    $first.attrs<fname> = 'Ann';
    $first.save;

    $second.attrs<lname> = 'Smith';
    $second.save;

    expect(User.find(saved.id).attrs<lname>).to.eq('Smith');
  }

  it 'writes a column marked dirty without a new value', {
    saved.attribute-will-change('lname');

    expect(updates-of()(-> { saved.save })[0].contains('lname')).to.be-truthy;
  }
}
