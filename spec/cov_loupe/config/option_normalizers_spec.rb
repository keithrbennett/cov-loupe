# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::OptionNormalizers do
  shared_examples 'a normalizer' do |method_name, valid_cases, invalid_cases|
    valid_cases.each do |input, expected|
      it "normalizes '#{input}' to #{expected}" do
        expect(described_class.send(method_name, input)).to eq(expected)
      end
    end

    normalized_cases = invalid_cases.map do |c|
      c.is_a?(Hash) ? [c.fetch(:input), c[:error_fragment]] : [c, c]
    end
    normalized_cases.each do |input_val, fragment_val|
      context "when input is #{input_val.inspect}" do
        let(:input) { input_val }
        let(:fragment) { fragment_val }

        it 'raises OptionParser::InvalidArgument' do
          expect { described_class.send(method_name, input) }
            .to raise_error(OptionParser::InvalidArgument) { |error|
              expect(error.message).to include('invalid argument')
              fragment_str = fragment.to_s
              unless fragment_str.empty?
                expect(error.message).to include(fragment_str)
              end
            }
        end
      end
    end
  end

  describe '.normalize_sort_order' do
    it_behaves_like 'a normalizer', :normalize_sort_order,
      [
        ['a', :ascending],
        ['ascending', :ascending],
        ['d', :descending],
        ['descending', :descending],
        ['ASCENDING', :ascending],
        ['Descending', :descending],
      ],
      ['invalid']
  end

  describe '.normalize_source_mode' do
    it_behaves_like 'a normalizer', :normalize_source_mode,
      [
        ['f', :full],
        ['full', :full],
        ['u', :uncovered],
        ['uncovered', :uncovered],
        ['n', nil],
        ['none', nil],
        ['N', nil],
        ['None', nil],
        ['FULL', :full],
        ['Uncovered', :uncovered],
      ],
      [nil, '', 'invalid']
  end

  describe '.normalize_error_mode' do
    it_behaves_like 'a normalizer', :normalize_error_mode,
      [
        ['off', :off],
        ['o', :off],
        ['log', :log],
        ['l', :log],
        ['debug', :debug],
        ['d', :debug],
        ['OFF', :off],
        ['Log', :log],
        ['DEBUG', :debug],
      ],
      %w[invalid on trace]
  end

  describe '.normalize_format' do
    it_behaves_like 'a normalizer', :normalize_format,
      [
        ['a', :amazing_print],
        ['amazing_print', :amazing_print],
        ['i', :inspect],
        ['inspect', :inspect],
        ['j', :json],
        ['json', :json],
        ['J', :pretty_json],
        ['pretty_json', :pretty_json],
        ['p', :puts],
        ['puts', :puts],
        ['P', :pretty_print],
        ['pretty_print', :pretty_print],
        ['t', :table],
        ['table', :table],
        ['y', :yaml],
        ['yaml', :yaml],
        ['TABLE', :table],
        ['Json', :json],
        ['Pretty_Print', :pretty_print],
      ],
      %w[invalid pretty-json pretty-print awesome_print ap]

    # A single character is a case-sensitive code ('J' is not 'j'), so it is not retried in lowercase.
    context 'with a single character not in the map' do
      it 'raises OptionParser::InvalidArgument' do
        expect { described_class.normalize_format('X') }
          .to raise_error(OptionParser::InvalidArgument)
      end
    end

    context 'with case-sensitive single-character shortcuts' do
      it "normalizes 'j' to :json and 'J' to :pretty_json distinctly" do
        expect(described_class.normalize_format('j')).to eq(:json)
        expect(described_class.normalize_format('J')).to eq(:pretty_json)
      end

      it "normalizes 'p' to :puts and 'P' to :pretty_print distinctly" do
        expect(described_class.normalize_format('p')).to eq(:puts)
        expect(described_class.normalize_format('P')).to eq(:pretty_print)
      end
    end
  end

  describe '.resolve_format_code' do
    it 'resolves each canonical long name to its short code' do
      described_class::FORMAT_LONG_NAMES.each do |long_name, code|
        expect(described_class.resolve_format_code(long_name)).to eq(code)
      end
    end

    it 'passes short codes through unchanged' do
      described_class::FORMAT_MAP.each_key do |code|
        expect(described_class.resolve_format_code(code)).to eq(code)
      end
    end

    it 'passes unrecognized values through unchanged' do
      expect(described_class.resolve_format_code('invalid_format')).to eq('invalid_format')
    end

    it 'stringifies non-string input before resolving' do
      expect(described_class.resolve_format_code(:json)).to eq('j')
    end
  end

  describe '.available_format_choices' do
    it 'returns one "code/long_name" entry per canonical format' do
      expect(described_class.available_format_choices).to eq(
        described_class::FORMAT_LONG_NAMES.map { |long_name, code| "#{code}/#{long_name}" }
      )
    end

    it 'preserves FORMAT_LONG_NAMES insertion (display) order' do
      codes = described_class.available_format_choices.map { |choice| choice.split('/').first }
      expect(codes).to eq(described_class::FORMAT_LONG_NAMES.values)
    end
  end

  describe 'FORMAT_LONG_NAMES insertion order' do
    it 'is alphabetical by downcased code, with lowercase before uppercase on ties' do
      actual_codes = described_class::FORMAT_LONG_NAMES.values
      expected_codes = actual_codes.sort_by { |code| [code.downcase, code.match?(/[A-Z]/) ? 1 : 0] }

      expect(actual_codes).to eq(expected_codes)
    end
  end

  describe 'constant maps' do
    %i[
      SORT_ORDER_MAP
      SOURCE_MODE_MAP
      ERROR_MODE_MAP
      FORMAT_LONG_NAMES
      FORMAT_MAP
      MODE_MAP
      OUTPUT_CHARS_MAP
    ].each do |const|
      it "has frozen #{const}" do
        expect(described_class.const_get(const)).to be_frozen
      end
    end
  end

  describe '.normalize_mode' do
    it 'normalizes cli and mcp values (full and short)' do
      {
        'cli' => :cli,
        'c'   => :cli,
        'mcp' => :mcp,
        'm'   => :mcp,
      }.each do |input, expected|
        expect(described_class.normalize_mode(input)).to eq(expected)
      end
    end

    it 'raises on invalid values' do
      expect { described_class.normalize_mode('bad') }
        .to raise_error(OptionParser::InvalidArgument)
    end
  end

  describe '.normalize_output_chars' do
    it_behaves_like 'a normalizer', :normalize_output_chars,
      [
        ['d', :default],
        ['default', :default],
        ['f', :fancy],
        ['fancy', :fancy],
        ['a', :ascii],
        ['ascii', :ascii],
        ['DEFAULT', :default],
        ['FANCY', :fancy],
        ['ASCII', :ascii],
        ['Ascii', :ascii],
      ],
      %w[invalid unicode utf8]
  end
end
