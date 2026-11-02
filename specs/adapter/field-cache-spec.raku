use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Instrumentation::Notifications;

%*ENV<DISABLE-SQL-LOG> = True;

my $adapter = DB.shared.adapter;
my $has-db  = $adapter.defined && $adapter.is-connected;

describe 'default-for-type, the starting value a column type takes', {
  if !$adapter.defined {
    pending 'no adapter configured for the type-default mapping';
  } else {
    let(:mapper, { $adapter });

    it 'starts an integer column at zero', {
      expect(mapper.default-for-type('integer')).to.eq(0);
    }

    it 'starts a character column at the empty string', {
      expect(mapper.default-for-type('character varying')).to.eq('');
    }

    it 'starts a text column at the empty string', {
      expect(mapper.default-for-type('text')).to.eq('');
    }

    it 'starts a numeric column at zero', {
      expect(mapper.default-for-type('numeric')).to.eq(0);
    }

    it 'starts a boolean column at False', {
      expect(mapper.default-for-type('boolean')).to.be-falsy;
    }

    it 'starts a timestamp column undefined', {
      expect(mapper.default-for-type('timestamp without time zone').defined).to.be-falsy;
    }

    it 'starts a date column undefined', {
      expect(mapper.default-for-type('date').defined).to.be-falsy;
    }

    it 'refuses a column type it does not recognize', {
      expect({ mapper.default-for-type('gobbledygook') }).to.throw;
    }
  }
}

describe 'parse-default-literal, the value text of a column default', {
  if !$adapter.defined {
    pending 'no adapter configured for the default parser';
  } else {
    let(:parser, { $adapter });

    it 'reads a bare number', {
      expect(parser.parse-default-literal('3')).to.eq('3');
    }

    it 'reads a negative decimal inside parentheses', {
      expect(parser.parse-default-literal('(-1.5)')).to.eq('-1.5');
    }

    it 'unquotes a string and its doubled quotes', {
      expect(parser.parse-default-literal("'it''s'")).to.eq("it's");
    }

    it 'drops a type cast after the literal', {
      expect(parser.parse-default-literal("'draft'::character varying")).to.eq('draft');
    }

    it 'reads a boolean keyword', {
      expect(parser.parse-default-literal('FALSE')).to.eq('FALSE');
    }

    it 'leaves an expression undefined', {
      expect(parser.parse-default-literal('CURRENT_TIMESTAMP').defined).to.be-falsy;
    }
  }
}

describe 'derived field caches over a table', {
  if !$has-db {
    pending 'no reachable database for the configured adapter';
  } else {
    let(:adapter, { $adapter });
    let(:table, { 'contracts' });

    before-each { $adapter.clear-schema-cache }

    it 'names every column of the table', {
      expect(adapter.get-field-objects(:table(table)).map(*.name).first(* eq 'name').defined).to.be-truthy;
    }

    it 'hands out the same Field object on a repeated call', {
      my $first = adapter.get-field-objects(:table(table))[0];

      expect(adapter.get-field-objects(:table(table))[0] === $first).to.be-truthy;
    }

    it 'issues no further query for a repeated call', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      adapter.get-field-objects(:table(table));
      my $after-first = @sql.elems;
      adapter.get-field-objects(:table(table));

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    it 'keys the field map by column name', {
      expect(adapter.get-field-map(:table(table)){'name'}.name).to.eq('name');
    }

    it 'shares the mapped Field with the field list', {
      my $listed = adapter.get-field-objects(:table(table)).first(*.name eq 'name');

      expect(adapter.get-field-map(:table(table)){'name'} === $listed).to.be-truthy;
    }

    it 'issues no further query for a repeated field map', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      adapter.get-field-map(:table(table));
      my $after-first = @sql.elems;
      adapter.get-field-map(:table(table));

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    it 'reports the column type in the type map', {
      expect(adapter.get-field-types(:table(table)){'name'})
        .to.eq(adapter.get-field-map(:table(table)){'name'}.type);
    }

    it 'issues no further query for a repeated type map', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      adapter.get-field-types(:table(table));
      my $after-first = @sql.elems;
      adapter.get-field-types(:table(table));

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    it 'leaves the primary key out of the attribute defaults', {
      expect(adapter.get-field-defaults(:table(table)){'id'}:exists).to.be-falsy;
    }

    it 'gives every other column a starting value', {
      my %defaults = adapter.get-field-defaults(:table(table));
      my @missing = adapter.get-field-objects(:table(table))
        .grep({ .name ne 'id' })
        .grep({ %defaults{.name}:!exists });

      expect(@missing.elems).to.eq(0);
    }

    it 'issues no further query for repeated defaults', {
      my @sql;
      my $sub = Notifications.subscribe('sql.active_record', -> %p { @sql.push: %p<sql> });

      adapter.get-field-defaults(:table(table));
      my $after-first = @sql.elems;
      adapter.get-field-defaults(:table(table));

      Notifications.unsubscribe($sub);
      expect(@sql.elems).to.eq($after-first);
    }

    context 'after a schema change clears the cache', {
      before-each {
        $adapter.get-field-objects(:table('contracts'));
        $adapter.exec('DROP TABLE IF EXISTS fc_widgets');
        $adapter.ddl-create-table('fc_widgets', [
          name  => { :string, limit => 64 },
          code  => { :string, limit => 64, null => False },
          stock => { :integer, null => False, default => 5 },
          grade => { :string, limit => 8, null => False, default => "it's" },
          listed => { :boolean, null => False, default => True },
        ]);
        $adapter.ddl-add-timestamps('fc_widgets');
      }

      after-each {
        try $adapter.exec('DROP TABLE IF EXISTS fc_widgets');
      }

      it 're-introspects the field list', {
        expect(adapter.get-field-objects(:table('fc_widgets')).map(*.name).first(* eq 'name').defined)
          .to.be-truthy;
      }

      it 're-introspects the field map', {
        expect(adapter.get-field-map(:table('fc_widgets')){'name'}.defined).to.be-truthy;
      }

      it 're-introspects the type map', {
        expect(adapter.get-field-types(:table('fc_widgets')){'name'}.defined).to.be-truthy;
      }

      it 're-introspects the defaults', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'name'}:exists).to.be-truthy;
      }

      it 'starts a nullable column undefined', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'name'}.defined).to.be-falsy;
      }

      it 'starts a NOT NULL column with no default undefined', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'code'}.defined).to.be-falsy;
      }

      it 'lists the NOT NULL columns with no default as required', {
        expect(adapter.required-columns(:table('fc_widgets'))).to.eq(('code',));
      }

      it 'starts a column with a database default at that default', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'stock'}).to.eq(5);
      }

      it 'starts a string column with a database default at that default', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'grade'}).to.eq("it's");
      }

      it 'starts a boolean column with a database default at that default', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'listed'}).to.be-truthy;
      }

      it 'starts a timestamp column with an expression default undefined', {
        expect(adapter.get-field-defaults(:table('fc_widgets')){'created_at'}.defined).to.be-falsy;
      }
    }
  }
}
