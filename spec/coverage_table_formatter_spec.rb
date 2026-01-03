# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/coverage_table_formatter'

RSpec.describe CovLoupe::CoverageTableFormatter do
  describe '.format' do
    context 'with valid coverage rows' do
      let(:rows) do
        [
          {
            'file' => 'lib/foo.rb',
            'percent_covered' => 100.0,
            'covered' => 10,
            'total' => 10,
            'stale' => false
          },
          {
            'file' => 'lib/bar.rb',
            'percent_covered' => 50.0,
            'covered' => 5,
            'total' => 10,
            'stale' => 'M'
          },
          {
            'file' => 'lib/baz.rb',
            'percent_covered' => 75.0,
            'covered' => 15,
            'total' => 20,
            'stale' => 'T'
          }
        ]
      end

      it 'returns a formatted table with box-drawing characters' do
        output = described_class.format(rows)

        aggregate_failures do
          %w[┌ ┬ ┐ │ ├ ┼ ┤ └ ┴ ┘].each do |char|
            expect(output).to include(char)
          end
        end
      end

      it 'includes column headers' do
        output = described_class.format(rows)

        aggregate_failures do
          %w[File % Covered Total Stale].each do |header|
            expect(output).to include(header)
          end
        end
      end

      it 'includes file paths' do
        output = described_class.format(rows)

        aggregate_failures do
          %w[lib/foo.rb lib/bar.rb lib/baz.rb].each do |path|
            expect(output).to include(path)
          end
        end
      end

      it 'includes coverage percentages with 2 decimal places' do
        output = described_class.format(rows)

        aggregate_failures do
          %w[100.00% 50.00% 75.00%].each do |percentage|
            expect(output).to include(percentage)
          end
        end
      end

      it 'includes covered and total line counts' do
        output = described_class.format(rows)

        [
          { pattern: /10.*10/, description: 'foo.rb: 10 covered, 10 total' },
          { pattern: /5.*10/, description: 'bar.rb: 5 covered, 10 total' },
          { pattern: /15.*20/, description: 'baz.rb: 15 covered, 20 total' }
        ].each do |test_case|
          expect(output).to match(test_case[:pattern]), test_case[:description]
        end
      end

      it 'includes stale indicators' do
        output = described_class.format(rows)

        expect(output).to include('M', 'T')  # Missing file, Timestamp mismatch
      end

      it 'includes summary counts footer' do
        output = described_class.format(rows)

        expect(output).to include('Files: total 3, ok 1, stale 2')
      end

      it 'includes staleness legend when stale files present' do
        output = described_class.format(rows)

        staleness_msg = 'Staleness: E = Error checking, M = Missing file, ' \
                        'T = Timestamp (source newer), L = Line count mismatch'
        expect(output).to include(staleness_msg)
      end

      it 'does not include staleness legend when no stale files' do
        non_stale_rows = [
          {
            'file' => 'lib/foo.rb',
            'percent_covered' => 100.0,
            'covered' => 10,
            'total' => 10,
            'stale' => false
          }
        ]

        output = described_class.format(non_stale_rows)

        expect(output).not_to include('Staleness:')
      end
    end

    context 'with empty rows' do
      it 'returns "No coverage data found" message' do
        output = described_class.format([])

        expect(output).to eq('No coverage data found')
      end
    end

    context 'with varying file path lengths' do
      let(:rows) do
        [
          {
            'file' => 'short.rb',
            'percent_covered' => 100.0,
            'covered' => 10,
            'total' => 10,
            'stale' => false
          },
          {
            'file' => 'very/long/path/to/some/deeply/nested/file.rb',
            'percent_covered' => 50.0,
            'covered' => 5,
            'total' => 10,
            'stale' => false
          }
        ]
      end

      it 'adjusts column widths to accommodate longest file path' do
        output = described_class.format(rows)

        # All rows should have the same total width
        lines = output.split("\n")
        data_lines = lines.select { |line| line.include?('│') }
        widths = data_lines.map(&:length).uniq

        expect(widths.size).to eq(1), 'All table rows should have the same width'
      end
    end

    context 'with varying number lengths' do
      let(:rows) do
        [
          {
            'file' => 'file1.rb',
            'percent_covered' => 99.99,
            'covered' => 9999,
            'total' => 10_000,
            'stale' => false
          },
          {
            'file' => 'file2.rb',
            'percent_covered' => 1.0,
            'covered' => 1,
            'total' => 100,
            'stale' => false
          }
        ]
      end

      it 'adjusts covered/total column widths to accommodate largest numbers' do
        output = described_class.format(rows)

        expect(output).to include('9999', '10000', '99.99%', '1.00%')
      end
    end
  end
end
