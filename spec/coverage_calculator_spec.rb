# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCalculator do
  describe '.summary' do
    it 'handles empty arrays' do
      expect(described_class.summary([]))
        .to include('percent_covered' => 100.0, 'total' => 0, 'covered' => 0)
    end

    it 'handles arrays with only nils' do
      expect(described_class.summary([nil, nil]))
        .to include('percent_covered' => 100.0, 'total' => 0, 'covered' => 0)
    end

    it 'coerces string values to integers' do
      expect(described_class.summary(['1', '0', nil]))
        .to include('percent_covered' => 50.0, 'total' => 2, 'covered' => 1)
    end

    it 'calculates correct percentage for mixed coverage' do
      expect(described_class.summary([1, 0, 1, nil, 2]))
        .to include('percent_covered' => 75.0, 'total' => 4, 'covered' => 3)
    end
  end

  describe '.uncovered' do
    it 'returns line numbers for uncovered lines' do
      arr = [1, 0, nil, 2]
      expect(described_class.uncovered(arr)).to eq([2])
    end

    it 'ignores nil entries' do
      arr = [nil, 0, nil, 0, nil]
      expect(described_class.uncovered(arr)).to eq([2, 4])
    end

    it 'returns empty array when all lines are covered' do
      arr = [1, 2, nil, 3]
      expect(described_class.uncovered(arr)).to eq([])
    end

    it 'uses 1-indexed line numbers' do
      arr = [0] # First line (index 0) is uncovered
      expect(described_class.uncovered(arr)).to eq([1])
    end
  end

  describe '.detailed' do
    it 'returns detailed line information' do
      arr = [1, 0, nil, 2]
      expect(described_class.detailed(arr)).to eq([
        { 'line' => 1, 'hits' => 1, 'covered' => true },
        { 'line' => 2, 'hits' => 0, 'covered' => false },
        { 'line' => 4, 'hits' => 2, 'covered' => true }
      ])
    end

    it 'ignores nil entries' do
      arr = [nil, 1, nil, nil, 0]
      expect(described_class.detailed(arr)).to eq([
        { 'line' => 2, 'hits' => 1, 'covered' => true },
        { 'line' => 5, 'hits' => 0, 'covered' => false }
      ])
    end

    it 'marks lines with 0 hits as not covered' do
      arr = [0, 1]
      result = described_class.detailed(arr)
      expect(result[0]['covered']).to be false
      expect(result[1]['covered']).to be true
    end

    it 'uses 1-indexed line numbers' do
      arr = [1]
      expect(described_class.detailed(arr).first['line']).to eq(1)
    end

    it 'includes all lines with 0 hits in the output' do
      arr = [0, 0, nil, 0]
      result = described_class.detailed(arr)
      expect(result).to eq([
        { 'line' => 1, 'hits' => 0, 'covered' => false },
        { 'line' => 2, 'hits' => 0, 'covered' => false },
        { 'line' => 4, 'hits' => 0, 'covered' => false }
      ])
    end

    it 'handles consecutive zero-hit lines correctly' do
      arr = [1, 0, 0, 0, 1]
      result = described_class.detailed(arr)
      expect(result.length).to eq(5)
      expect(result[1..3]).to all(include('hits' => 0, 'covered' => false))
    end

    it 'coerces string "0" values to integer zero' do
      arr = ['0', '1', nil, '0']
      result = described_class.detailed(arr)
      expect(result).to eq([
        { 'line' => 1, 'hits' => 0, 'covered' => false },
        { 'line' => 2, 'hits' => 1, 'covered' => true },
        { 'line' => 4, 'hits' => 0, 'covered' => false }
      ])
    end

    it 'returns empty array for all-nil coverage' do
      arr = [nil, nil, nil]
      expect(described_class.detailed(arr)).to eq([])
    end
  end
end
