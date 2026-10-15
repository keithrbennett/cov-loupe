# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::StaleStatus do
  describe '.stale?' do
    it 'returns false for ok status' do
      expect(described_class.stale?('ok')).to be(false)
    end

    it 'returns true for stale statuses' do
      %w[deleted newer length_mismatch unreadable].each do |status|
        expect(described_class.stale?(status)).to be(true)
      end
    end

    it 'raises when status is missing' do
      expect { described_class.stale?(nil) }
        .to raise_error(ArgumentError, /Stale status is missing/)
    end

    it 'raises when status is not a string' do
      expect { described_class.stale?(:ok) }
        .to raise_error(ArgumentError, /Stale status must be a String/)
    end

    it 'raises when status is unknown' do
      expect { described_class.stale?('stale') }
        .to raise_error(ArgumentError, /Unknown stale status/)
    end
  end

  describe '.normalize' do
    it 'permits exactly the unified status vocabulary' do
      expect(described_class::VALID_STATUSES).to eq(%w[ok deleted newer length_mismatch unreadable])
    end

    [
      { status: 'ok',              constant: :OK },
      { status: 'deleted',         constant: :DELETED },
      { status: 'newer',           constant: :NEWER },
      { status: 'length_mismatch', constant: :LENGTH_MISMATCH },
      { status: 'unreadable',      constant: :UNREADABLE },
    ].each do |tc|
      it "accepts '#{tc[:status]}' (StaleStatus::#{tc[:constant]})" do
        expect(described_class.const_get(tc[:constant])).to eq(tc[:status])
        expect(described_class.normalize(tc[:status])).to eq(tc[:status])
      end
    end

    # Pre-v7 names: 'missing' became 'deleted', 'error' became 'unreadable'.
    %w[missing error missing_from_disk].each do |status|
      it "rejects the retired status '#{status}'" do
        expect { described_class.normalize(status) }
          .to raise_error(ArgumentError, /Unknown stale status: "#{status}"/)
      end
    end

    it 'no longer defines MISSING_FROM_DISK' do
      expect(described_class.const_defined?(:MISSING_FROM_DISK)).to be(false)
    end
  end
end
