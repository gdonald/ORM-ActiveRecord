use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Text::Inflector;
use ORM::ActiveRecord::Support::Utils;

Text::Inflector.inflections: {
  .irregular('cow', 'kine');
}

describe 'process-wide inflection overrides added before the first lookup', {
  it 'change the table name of a model class', {
    expect(Utils.tableize('Cow')).to.eq('kine');
  }

  it 'change the foreign key built from a table name', {
    expect(Utils.to-foreign-key('kine')).to.eq('cow_id');
  }
}
