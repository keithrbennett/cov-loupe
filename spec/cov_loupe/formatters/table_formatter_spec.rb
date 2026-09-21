# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::TableFormatter do
  describe '.format' do
    it 'returns a friendly message when no rows are provided' do
      result = described_class.format(headers: %w[Column], rows: [])
      expect(result).to eq('No data to display')
    end

    it 'aligns each column according to the provided alignments' do
      headers = %w[Left Right Center]
      rows = [%w[x 1 ok]]

      output = described_class.format(
        headers:    headers,
        rows:       rows,
        alignments: %i[left right center]
      )

      body_line = output.lines[3] # first data row after borders/header
      # Split by vertical bars to inspect each rendered cell without the borders.
      cells = body_line.split('│')[1..]
      cells.pop # drop trailing empty string after final separator

      trimmed = cells.map(&:strip)
      expect(trimmed).to eq(%w[x 1 ok])
      expect(cells[0][1..-2]).to eq('x   ')   # left aligned -> trailing spaces
      expect(cells[1][1..-2]).to eq('    1')  # right aligned -> leading spaces
      expect(cells[2][1..-2]).to eq('  ok  ') # centered -> spaces on both sides
    end
  end

  describe '.format column widths and borders' do
    [
      {
        desc:    'sizes a column from data that is longer than its header',
        headers: %w[A],
        rows:    [%w[longer]],
        table:   <<~TABLE,
          +--------+
          | A      |
          +--------+
          | longer |
          +--------+
        TABLE
      },
      {
        desc:    'sizes a column from a header that is longer than its data',
        headers: %w[Header],
        rows:    [%w[x]],
        table:   <<~TABLE,
          +--------+
          | Header |
          +--------+
          | x      |
          +--------+
        TABLE
      },
      {
        desc:       'sizes each column independently and joins columns with junction characters',
        headers:    %w[Name Qty],
        rows:       [%w[apple 3], %w[fig 12]],
        alignments: %i[left right],
        table:      <<~TABLE,
          +-------+-----+
          | Name  | Qty |
          +-------+-----+
          | apple |   3 |
          | fig   |  12 |
          +-------+-----+
        TABLE
      },
    ].each do |tc|
      it tc[:desc] do
        output = described_class.format(headers: tc[:headers], rows: tc[:rows],
          alignments: tc[:alignments], output_chars: :ascii)

        expect(output).to eq(tc[:table].chomp)
      end
    end
  end

  describe '.format_vertical' do
    it 'renders key/value pairs as a two-column table' do
      result = described_class.format_vertical({ 'foo' => 1, 'bar' => 2 })
      expect(result).to include('Key', 'Value', 'foo', 'bar', '1', '2')
    end
  end

  describe '.align_cell' do
    it 'right-aligns content' do
      expect(described_class.send(:align_cell, '7', 4, :right)).to eq('   7')
    end

    it 'centers content' do
      expect(described_class.send(:align_cell, 'mid', 5, :center)).to eq(' mid ')
    end

    it 'left-aligns by default' do
      expect(described_class.send(:align_cell, 'abc', 5, :unknown)).to eq('abc  ')
    end
  end

  describe 'output_chars modes' do
    let(:headers) { %w[Name Value] }
    let(:rows) { [['café', '→']] }

    describe 'output_chars: :ascii' do
      it 'uses ASCII border characters' do
        result = described_class.format(headers: headers, rows: rows, output_chars: :ascii)

        aggregate_failures do
          expect(result).to include('+')
          expect(result).to include('-')
          expect(result).to include('|')
          expect(result).not_to include("\u250C") # top-left corner
          expect(result).not_to include("\u2500") # horizontal
          expect(result).not_to include("\u2502") # vertical
        end
      end

      it 'converts cell contents to ASCII' do
        result = described_class.format(headers: headers, rows: rows, output_chars: :ascii)

        aggregate_failures do
          expect(result).not_to include('é')
          expect(result).not_to include('→')
          expect(result).to include('cafe') # é transliterated
          expect(result).to include('->') # → transliterated
        end
      end
    end

    describe 'output_chars: :fancy' do
      it 'uses Unicode box-drawing characters' do
        result = described_class.format(headers: headers, rows: rows, output_chars: :fancy)

        aggregate_failures do
          expect(result).to include("\u250C") # top-left corner
          expect(result).to include("\u2500") # horizontal
          expect(result).to include("\u2502") # vertical
        end
      end

      it 'preserves Unicode in cell contents' do
        result = described_class.format(headers: headers, rows: rows, output_chars: :fancy)

        expect(result).to include('café')
        expect(result).to include('→')
      end
    end
  end
end
