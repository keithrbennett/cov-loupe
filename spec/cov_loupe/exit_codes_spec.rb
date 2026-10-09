# frozen_string_literal: true

require 'cov_loupe'

RSpec.describe CovLoupe::ExitCodes do
  # These values are a documented public contract (docs/user/CLI_USAGE.md#exit-codes).
  {
    SUCCESS:           0,
    ERROR:             1,
    USAGE:             2,
    VALIDATION_FAILED: 3,
    PREDICATE_ERROR:   4,
  }.each do |name, value|
    it "defines #{name} as #{value}" do
      expect(described_class.const_get(name)).to eq(value)
    end
  end
end
