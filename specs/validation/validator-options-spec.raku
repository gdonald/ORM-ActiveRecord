use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::Validations::Validator;

%*ENV<DISABLE-SQL-LOG> = True;

class OptionsOwner { }

# A validator's declared options never change, so they are read out of its
# params once rather than on every validation of every record.
describe 'the options a validator was declared with', {
  let(:field, { Field.new(:name('username'), :type('character varying')) });

  let(:validator, {
    Validator.new(
      :klass(OptionsOwner),
      :field(field),
      :params({ :presence, exclusion => { in => <admin> }, message => 'nope', :strict }),
    );
  });

  it 'reads a nested option', {
    expect(validator.options<exclusion><in>.list).to.eq(('admin',));
  }

  it 'reads a message', {
    expect(validator.options<msg>).to.eq('nope');
  }

  it 'reads a flag', {
    expect(validator.options<strict>).to.be-truthy;
  }

  it 'defaults a flag that was not declared', {
    expect(validator.options<allow-nil>).to.be-falsy;
  }

  it 'defaults the condition to one that passes', {
    expect(validator.options<cond-if>()).to.be-truthy;
  }

  it 'defaults the negative condition to one that does not fire', {
    expect(validator.options<cond-unless>()).to.be-falsy;
  }

  it 'hands back the same parse on a second read', {
    expect(validator.options === validator.options).to.be-truthy;
  }

  it 'names the class it belongs to', {
    expect(validator.klass-name).to.eq(OptionsOwner.raku);
  }

  it 'hands back the same name on a second read', {
    expect(validator.klass-name).to.eq(validator.klass-name);
  }

  context 'an each-validator', {
    let(:each-validator, {
      EachValidator.new(
        :klass(OptionsOwner),
        :fields(['username']),
        :block(-> $o, $n, $v { }),
        :params({ :strict, on => { create => True } }),
      );
    });

    it 'reads its flag', {
      expect(each-validator.options<strict>).to.be-truthy;
    }

    it 'reads its context map', {
      expect(each-validator.options<ons><create>).to.be-truthy;
    }

    it 'hands back the same parse on a second read', {
      expect(each-validator.options === each-validator.options).to.be-truthy;
    }
  }
}
