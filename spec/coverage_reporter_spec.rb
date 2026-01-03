# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageReporter do
  let(:model) { instance_double(CovLoupe::CoverageModel) }
  # Data is pre-sorted by percentage ascending (as model.list returns)
  let(:files_data) do
    [
      { 'file' => '/project/lib/zero.rb',   'percent_covered' =>  0.0, 'covered' =>  0, 'total' => 10 },
      { 'file' => '/project/lib/low.rb',    'percent_covered' => 25.0, 'covered' =>  5, 'total' => 20 },
      { 'file' => '/project/lib/medium.rb', 'percent_covered' => 60.0, 'covered' => 12, 'total' => 20 },
      { 'file' => '/project/lib/high.rb',   'percent_covered' => 95.0, 'covered' => 19, 'total' => 20 }
    ]
  end

  before do
    allow(model).to receive(:list).with(sort_order: :ascending).and_return({
      'files' => files_data,
      'skipped_files' => [],
      'missing_tracked_files' => [],
      'newer_files' => [],
      'deleted_files' => []
    })
    allow(model).to receive(:relativize) do |files|
      files.map { |f| f.merge('file' => f['file'].sub('/project/', '')) }
    end
  end

  describe '.report' do
    it 'returns formatted low coverage files string' do
      result = described_class.report(threshold: 80, count: 5, model: model)

      expect(result).to be_a(String)
      expect(result).to include('Lowest coverage files (< 80%):')
      expect(result).to include('lib/zero.rb')
    end

    it 'includes files below threshold sorted by coverage ascending' do
      result = described_class.report(threshold: 80, count: 5, model: model)

      expect(result).to include('lib/zero.rb', 'lib/low.rb', 'lib/medium.rb')
      expect(result).not_to include('lib/high.rb')
    end

    it 'respects count parameter' do
      result = described_class.report(threshold: 80, count: 2, model: model)

      expect(result).to include('lib/zero.rb')
      expect(result).to include('lib/low.rb')
      expect(result).not_to include('lib/medium.rb')
    end

    it 'returns nil when no files below threshold' do
      result = described_class.report(threshold: 0, count: 5, model: model)

      expect(result).to be_nil
    end

    it 'uses threshold in header' do
      result = described_class.report(threshold: 90, count: 5, model: model)

      expect(result).to include('< 90%')
    end

    it 'uses default threshold of 80' do
      result = described_class.report(count: 5, model: model)

      expect(result).to include('< 80%')
      expect(result).not_to include('lib/high.rb')
    end

    it 'uses default count of 5' do
      result = described_class.report(threshold: 100, model: model)

      # All 4 files are below 100%
      expect(result).to include('lib/zero.rb')
      expect(result).to include('lib/high.rb')
    end

    it 'relativizes file paths' do
      result = described_class.report(threshold: 80, count: 5, model: model)

      expect(result).to include('lib/zero.rb')
      expect(result).not_to include('/project/')
    end

    it 'aligns percentages correctly' do
      result = described_class.report(threshold: 100, count: 5, model: model)
      lines = result.split("\n")

      # lines[0] is empty (leading newline), lines[1] is header, lines[2..] are data
      expect(lines[2]).to match(/^\s+0\.0%/)
      expect(lines[3]).to match(/^\s+25\.0%/)
    end
  end

  describe 'module_function behavior' do
    it 'report is available as a module method' do
      expect(described_class).to respond_to(:report)
    end

    it 'report is available as a private instance method when included' do
      klass = Class.new { include CovLoupe::CoverageReporter }
      expect(klass.private_instance_methods).to include(:report)
    end
  end
end
