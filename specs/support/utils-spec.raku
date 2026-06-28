use lib 'lib';
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
