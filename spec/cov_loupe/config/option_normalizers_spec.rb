# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::OptionNormalizers do
  shared_examples 'a normalizer' do |method_name, valid_cases, invalid_cases, invalid_return: nil|
    context 'with strict mode (default)' do
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

    context 'with strict: false' do
      it "returns #{invalid_return.inspect} for invalid values" do
        expect(described_class.send(method_name, 'invalid', strict: false)).to eq(invalid_return)
      end

      it 'still normalizes valid values' do
        input, expected = valid_cases.first
        expect(described_class.send(method_name, input, strict: false)).to eq(expected)
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
      %w[invalid on trace],
      invalid_return: :log

    context 'with strict: false and default: :log' do
      [['invalid', :log], [nil, :log]].each do |input, expected|
        it "returns default #{expected} for #{input.inspect}" do
          expect(described_class.normalize_error_mode(input, strict: false,
            default: :log)).to eq(expected)
        end
      end
    end

    context 'with custom default' do
      it 'returns custom default for invalid values when not strict' do
        expect(described_class.normalize_error_mode('invalid', strict: false,
          default: :off)).to eq(:off)
      end
    end
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

    # Single characters not in FORMAT_MAP are rejected in strict mode but return nil in lenient mode.
    # This tests the branch at lines 110-112 that handles unknown single-char shortcuts.
    context 'with single-character not in map and strict: false' do
      it 'returns nil for unknown single character in lenient mode' do
        expect(described_class.normalize_format('X', strict: false)).to be_nil
      end
    end

    context 'with single-character not in map and strict: true' do
      it 'raises OptionParser::InvalidArgument for unknown single character' do
        expect { described_class.normalize_format('X', strict: true) }
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

  describe 'constant maps' do
    %i[
      SORT_ORDER_MAP
      SOURCE_MODE_MAP
      ERROR_MODE_MAP
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

    it 'raises on invalid values in strict mode' do
      expect { described_class.normalize_mode('bad') }
        .to raise_error(OptionParser::InvalidArgument)
    end

    it 'returns default when not strict and invalid' do
      expect(described_class.normalize_mode('bad', strict: false, default: :cli)).to eq(:cli)
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
      %w[invalid unicode utf8],
      invalid_return: :default

    context 'with strict: false and default: :default' do
      [['invalid', :default], [nil, :default], ['', :default]].each do |input, expected|
        it "returns default #{expected} for #{input.inspect}" do
          expect(described_class.normalize_output_chars(input, strict: false,
            default: :default)).to eq(expected)
        end
      end
    end

    context 'with custom default' do
      it 'returns custom default for invalid values when not strict' do
        expect(described_class.normalize_output_chars('invalid', strict: false,
          default: :ascii)).to eq(:ascii)
      end
    end
  end
end
