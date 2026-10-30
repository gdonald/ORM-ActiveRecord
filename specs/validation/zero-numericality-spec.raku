use lib 'lib';
use lib 'specs/lib';
use BDD::Behave;
use Validation::ZeroNumericality;

%*ENV<DISABLE-SQL-LOG> = True;

sub valid-attrs(*%overrides) {
  %( above_zero => 1, at_least_zero => 0, below_zero => -1, at_most_zero => 0, balance => 0, |%overrides );
}

describe 'numericality with a threshold of 0', {
  after-each { Meter.destroy-all }

  context 'with every value on the valid side of 0', {
    let(:meter, { Meter.build(valid-attrs) });

    it 'is valid', {
      expect(meter.is-valid).to.be-truthy;
    }
  }

  context 'gt 0 given 0', {
    let(:meter, { Meter.build(valid-attrs(above_zero => 0)) });

    it 'is invalid', {
      expect(meter.is-invalid).to.be-truthy;
    }

    it 'reports "more than 0 required"', {
      meter.is-invalid;
      expect(meter.errors.above_zero[0]).to.eq('more than 0 required');
    }
  }

  context 'gte 0 given -5', {
    let(:meter, { Meter.build(valid-attrs(at_least_zero => -5)) });

    it 'is invalid', {
      expect(meter.is-invalid).to.be-truthy;
    }

    it 'reports "0 or more required"', {
      meter.is-invalid;
      expect(meter.errors.at_least_zero[0]).to.eq('0 or more required');
    }

    it 'does not save', {
      expect(meter.save).to.be-falsy;
    }
  }

  context 'gte 0 given 0', {
    let(:meter, { Meter.build(valid-attrs(at_least_zero => 0)) });

    it 'is valid', {
      expect(meter.is-valid).to.be-truthy;
    }
  }

  context 'lt 0 given 0', {
    let(:meter, { Meter.build(valid-attrs(below_zero => 0)) });

    it 'is invalid', {
      expect(meter.is-invalid).to.be-truthy;
    }

    it 'reports "less than 0 required"', {
      meter.is-invalid;
      expect(meter.errors.below_zero[0]).to.eq('less than 0 required');
    }
  }

  context 'lte 0 given 5', {
    let(:meter, { Meter.build(valid-attrs(at_most_zero => 5)) });

    it 'is invalid', {
      expect(meter.is-invalid).to.be-truthy;
    }

    it 'reports "0 or less required"', {
      meter.is-invalid;
      expect(meter.errors.at_most_zero[0]).to.eq('0 or less required');
    }
  }

  context 'gte 0 on a decimal column given -0.5', {
    let(:meter, { Meter.build(valid-attrs(balance => -0.5)) });

    it 'is invalid', {
      expect(meter.is-invalid).to.be-truthy;
    }

    it 'reports "0 or more required"', {
      meter.is-invalid;
      expect(meter.errors.balance[0]).to.eq('0 or more required');
    }
  }

  context 'gte 0 on a decimal column given 0.5', {
    let(:meter, { Meter.build(valid-attrs(balance => 0.5)) });

    it 'is valid', {
      expect(meter.is-valid).to.be-truthy;
    }
  }
}
