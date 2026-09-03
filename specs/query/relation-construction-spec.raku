use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Instrumentation::Notifications;
use Models::Page;
use Models::User;

%*ENV<DISABLE-SQL-LOG> = True;

describe 'Model.belongs-to-names, the declared belongs-to associations of a class', {
  it 'names a plain belongs-to', {
    expect(Page.belongs-to-names{'user'}).to.be-truthy;
  }

  it 'names a second belongs-to on the same class', {
    expect(Page.belongs-to-names{'autosave-user'}).to.be-truthy;
  }

  it 'leaves out a name the class does not declare', {
    expect(Page.belongs-to-names{'nonesuch'}).to.be-falsy;
  }

  it 'is empty for a class that declares none', {
    expect(User.belongs-to-names.elems).to.eq(0);
  }

  it 'hands back the same set on a repeated call', {
    my $first = Page.belongs-to-names;

    expect(Page.belongs-to-names === $first).to.be-truthy;
  }

  it 'still rewrites a belongs-to name to its foreign key in a where clause', {
    expect(Page.where({ user => 7 }).where-values{'user_id'}).to.eq(7);
  }
}

describe 'building a relation', {
  let(:sql-of, {
    -> &block {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });
      block();
      Notifications.unsubscribe($sub);
      @sql;
    }
  });

  # The belongs-to names of a class are derived from one instance the first
  # time any relation needs them, so warm them here to keep each example
  # measuring only what building a relation costs.
  before-each {
    Page.belongs-to-names;
    DB.shared.adapter.clear-schema-cache;
  }

  it 'queries nothing until the relation is asked for something', {
    expect(sql-of()(-> { Page.all }).elems).to.eq(0);
  }

  it 'queries nothing to add a condition', {
    expect(sql-of()(-> { Page.all.where({ id => 1 }) }).elems).to.eq(0);
  }

  it 'reads the column list when the relation names its fields', {
    my $relation = Page.all;

    expect(sql-of()(-> { $relation.all-fields }).elems).to.be-greater-than(0);
  }

  it 'reads the column list only once', {
    my $relation = Page.all;
    $relation.all-fields;

    expect(sql-of()(-> { $relation.all-fields }).elems).to.eq(0);
  }

  it 'names every column of the table', {
    expect(Page.all.all-fields.map(*.name).first(* eq 'name').defined).to.be-truthy;
  }

  it 'narrows the named fields to the selected columns', {
    expect(Page.all.select('name').fields-of.map(*.name).list).to.eq(('name',));
  }

  it 'renarrows the named fields when the selection grows', {
    my $relation = Page.all.select('name');
    $relation.fields-of;

    expect($relation.select('id').fields-of.map(*.name).sort.list).to.eq(('id', 'name'));
  }

  it 'falls back to every column when the selection names no column of the table', {
    expect(Page.all.select('COUNT(*) AS c').fields-of.elems)
      .to.eq(Page.all.all-fields.elems);
  }
}
