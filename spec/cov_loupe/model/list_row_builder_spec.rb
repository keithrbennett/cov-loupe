# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/model/list_row_builder'

RSpec.describe CovLoupe::ListRowBuilder do
  let(:logger) { instance_double(CovLoupe::Logger, safe_log: true) }

  describe '.lines_from_entry' do
    [
      ['a valid lines array', { 'lines' => [1, 0, nil, 2] }, [1, 0, nil, 2]],
      ['non-integer elements', { 'lines' => ['foo', 3.5, {}, nil] }, nil],
      ['a non-Hash entry', [1, 2], nil],
      ['a missing lines key', {}, nil],
    ].each do |description, entry, expected|
      it "returns #{expected.inspect} for #{description}" do
        expect(described_class.lines_from_entry(entry, logger: logger)).to eq(expected)
      end
    end

    it 'returns nil and logs when lines is not an array' do
      expect(described_class.lines_from_entry({ 'lines' => 'not an array' }, logger: logger)).to be_nil
      expect(logger).to have_received(:safe_log).with(/Invalid coverage lines encountered \(not an array\)/)
    end
  end

  describe '#build' do
    subject(:result) do
      described_class.new(coverage_map, root: root, volume_case_sensitive: true, logger: logger).build
    end

    let(:root) { File.expand_path('/proj') }
    let(:good_path) { File.join(root, 'lib/good.rb') }
    let(:bad_path) { File.join(root, 'lib/bad.rb') }
    let(:coverage_map) do
      {
        good_path => { 'lines' => [1, 0, nil] },
        bad_path  => { 'lines' => ['corrupt'] },
      }
    end

    it 'builds summary rows and lines for readable entries' do
      aggregate_failures do
        expect(result.rows).to eq([
          { 'file' => good_path, 'covered' => 1, 'total' => 2, 'percentage' => 50.0 },
        ])
        expect(result.lines_by_path).to eq(good_path => [1, 0, nil])
      end
    end

    it 'records and logs entries that cannot be read instead of raising' do
      aggregate_failures do
        expect(result.errors.keys).to eq([bad_path])
        expect(result.errors[bad_path]).to be_a(CovLoupe::CoverageDataError)
        expect(result.skipped_rows).to eq([{
          'file'        => bad_path,
          'error'       => result.errors[bad_path].message,
          'error_class' => 'CovLoupe::CoverageDataError',
        }])
        expect(logger).to have_received(:safe_log)
          .with(/Skipping coverage row for #{Regexp.escape(bad_path)}/)
      end
    end
  end
end
