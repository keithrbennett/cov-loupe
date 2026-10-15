# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/coverage/coverage_table_formatter'

RSpec.describe CovLoupe::CoverageTableFormatter do
  describe '.format' do
    context 'with valid coverage rows' do
      let(:rows) do
        [
          {
            'file'       => 'lib/foo.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
          {
            'file'       => 'lib/bar.rb',
            'percentage' => 50.0,
            'covered'    => 5,
            'total'      => 10,
            'stale'      => 'deleted',
          },
          {
            'file'       => 'lib/baz.rb',
            'percentage' => 75.0,
            'covered'    => 15,
            'total'      => 20,
            'stale'      => 'newer',
          },
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
          { pattern: /15.*20/, description: 'baz.rb: 15 covered, 20 total' },
        ].each do |test_case|
          expect(output).to match(test_case[:pattern]), test_case[:description]
        end
      end

      it 'includes stale indicators' do
        output = described_class.format(rows)

        expect(output).to include('deleted', 'newer') # Deleted file, Timestamp mismatch
      end

      it 'includes summary counts footer' do
        output = described_class.format(rows)

        expect(output).to include('Files: total 3, ok 1, stale 2')
      end

      it 'includes staleness legend when stale files present' do
        output = described_class.format(rows)

        staleness_msg = 'Staleness: deleted, newer, length_mismatch, unreadable'
        expect(output).to include(staleness_msg)
      end

      it 'does not include staleness legend when no stale files' do
        non_stale_rows = [
          {
            'file'       => 'lib/foo.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
        ]

        output = described_class.format(non_stale_rows)

        expect(output).not_to include('Staleness:')
      end

      it 'displays blank for \"ok\" staleness status (regression test for issue #4)' do
        ok_rows = [
          {
            'file'       => 'lib/foo.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
          {
            'file'       => 'lib/bar.rb',
            'percentage' => 80.0,
            'covered'    => 8,
            'total'      => 10,
            'stale'      => 'ok',
          },
        ]

        output = described_class.format(ok_rows)

        # Extract data rows (lines with file paths, excluding header and footer)
        data_lines = output.split("\n").select do |line|
          line.include?('│') && !line.include?('File') && !line.include?('─')
        end

        # The table data rows should not display "ok" in the stale column
        # This would fail if the formatter reverted to displaying the symbol name
        data_lines.each do |line|
          expect(line).not_to include(' ok ')
        end

        # But the summary footer should still mention "ok 2"
        expect(output).to include('Files: total 2, ok 2, stale 0')
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
            'file'       => 'short.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
          {
            'file'       => 'very/long/path/to/some/deeply/nested/file.rb',
            'percentage' => 50.0,
            'covered'    => 5,
            'total'      => 10,
            'stale'      => 'ok',
          },
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

    context 'with nil percentage' do
      let(:rows) do
        [
          {
            'file'       => 'empty.rb',
            'percentage' => nil,
            'covered'    => 0,
            'total'      => 0,
            'stale'      => 'ok',
          },
        ]
      end

      it 'displays "n/a" aligned to the right' do
        output = described_class.format(rows)
        # Check alignment: should be padded to 8 chars (default pct width)
        # "     n/a"
        expect(output).to include('     n/a')
      end
    end

    context 'with varying number lengths' do
      let(:rows) do
        [
          {
            'file'       => 'file1.rb',
            'percentage' => 99.99,
            'covered'    => 9999,
            'total'      => 10_000,
            'stale'      => 'ok',
          },
          {
            'file'       => 'file2.rb',
            'percentage' => 1.0,
            'covered'    => 1,
            'total'      => 100,
            'stale'      => 'ok',
          },
        ]
      end

      it 'adjusts covered/total column widths to accommodate largest numbers' do
        output = described_class.format(rows)

        expect(output).to include('9999', '10000', '99.99%', '1.00%')
      end
    end

    context 'with long staleness labels' do
      let(:rows) do
        [
          {
            'file'       => 'lib/foo.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
          {
            'file'       => 'lib/bar.rb',
            'percentage' => 50.0,
            'covered'    => 5,
            'total'      => 10,
            'stale'      => 'deleted',
          },
          {
            'file'       => 'lib/baz.rb',
            'percentage' => 75.0,
            'covered'    => 15,
            'total'      => 20,
            'stale'      => 'length_mismatch',
          },
        ]
      end

      it 'adjusts stale column width to accommodate longest staleness label' do
        output = described_class.format(rows)

        # All rows should have the same total width
        lines = output.split("\n")
        data_lines = lines.select { |line| line.include?('│') }
        widths = data_lines.map(&:length).uniq

        expect(widths.size).to eq(1), 'All table rows should have the same width'
      end

      it 'displays the full length_mismatch label without overflow' do
        output = described_class.format(rows)

        expect(output).to include('length_mismatch')
      end

      it 'maintains proper table alignment with long labels' do
        output = described_class.format(rows)

        # Extract border lines (they should all be the same length)
        lines = output.split("\n")
        border_lines = lines.select { |line| line.include?('─') }
        border_widths = border_lines.map(&:length).uniq

        expect(border_widths.size).to eq(1), 'All border lines should have the same width'
      end
    end

    context 'with output_chars option' do
      let(:rows) do
        [
          {
            'file'       => 'lib/foo.rb',
            'percentage' => 100.0,
            'covered'    => 10,
            'total'      => 10,
            'stale'      => 'ok',
          },
        ]
      end

      context 'with output_chars: :fancy' do
        it 'uses Unicode box-drawing characters' do
          output = described_class.format(rows, output_chars: :fancy)

          aggregate_failures do
            expect(output).to include('┌')
            expect(output).to include('─')
            expect(output).to include('│')
            expect(output).to include('┘')
          end
        end
      end

      context 'with output_chars: :ascii' do
        it 'uses ASCII characters for borders' do
          output = described_class.format(rows, output_chars: :ascii)

          aggregate_failures do
            # ASCII borders should use +, -, |
            expect(output).to include('+')
            expect(output).to include('-')
            expect(output).to include('|')
            # Should not include Unicode box-drawing
            expect(output).not_to include('┌')
            expect(output).not_to include('─')
            expect(output).not_to include('│')
          end
        end

        it 'still includes correct data' do
          output = described_class.format(rows, output_chars: :ascii)

          expect(output).to include('lib/foo.rb')
          expect(output).to include('100.00%')
          expect(output).to include('File')
        end
      end

      context 'with output_chars: :default' do
        it 'uses Unicode box-drawing when stdout encoding is UTF-8' do
          allow($stdout).to receive(:external_encoding).and_return(Encoding::UTF_8)

          output = described_class.format(rows, output_chars: :default)

          expect(output).to include('┌')
        end
      end
    end
  end
end
