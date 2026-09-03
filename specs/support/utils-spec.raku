use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Model;

describe 'Utils.underscore', {
  it 'snake_cases a camel-case name', {
    expect(Utils.underscore('PageTag')).to.eq('page_tag');
  }

  it 'lowercases a single word', {
    expect(Utils.underscore('User')).to.eq('user');
  }

  it 'strips the namespace', {
    expect(Utils.underscore('Foo::HotItem')).to.eq('hot_item');
  }
}

describe 'Utils.tableize', {
  it 'snake_cases and pluralizes a camel-case name', {
    expect(Utils.tableize('PageTag')).to.eq('page_tags');
  }

  it 'pluralizes a single word', {
    expect(Utils.tableize('User')).to.eq('users');
  }
}

describe 'a model table name', {
  it 'derives a snake_case plural for a multi-word model', {
    my class WidgetPart is Model { }
    expect(WidgetPart.table-name).to.eq('widget_parts');
  }
}

# Each of these is a pure function of a name, and a model derives its table name
# on every instantiation, so the string work is done once per name.
describe 'name derivations repeated for the same name', {
  it 'gives the same table name every time', {
    expect(Utils.tableize('PageTag')).to.eq(Utils.tableize('PageTag'));
  }

  it 'gives the same singular every time', {
    expect(Utils.singular('pages')).to.eq(Utils.singular('pages'));
  }

  it 'singularizes a plural', {
    expect(Utils.singular('pages')).to.eq('page');
  }

  it 'leaves a name with no trailing s alone', {
    expect(Utils.singular('person')).to.eq('person');
  }

  it 'gives the same foreign key every time', {
    expect(Utils.to-foreign-key('pages')).to.eq(Utils.to-foreign-key('pages'));
  }

  it 'builds a foreign key from a table name', {
    expect(Utils.to-foreign-key('pages')).to.eq('page_id');
  }

  it 'keeps distinct names apart', {
    expect(Utils.tableize('Page') eq Utils.tableize('PageTag')).to.be-falsy;
  }
}
