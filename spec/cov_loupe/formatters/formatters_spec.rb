# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Formatters do
  describe '.format' do
    let(:obj) { { 'foo' => 'bar' } }

    it 'raises ArgumentError for unknown format' do
      expect { described_class.format(obj, :unknown) }
        .to raise_error(ArgumentError, /Unknown format: unknown/)
    end

    [
      [:json, '{"foo":"bar"}', :eq],
      [:pretty_json, "{\n  \"foo\": \"bar\"\n}", :include],
      [:table, { 'foo' => 'bar' }, :eq],
      [:yaml, "---\nfoo: bar\n", :include],
      [:inspect, '{"foo"=>"bar"}', :eq],
      [:puts, "{\"foo\"=>\"bar\"}\n", :eq],
      [:pretty_print, "{\"foo\"=>\"bar\"}\n", :eq],
    ].each do |format, expected, matcher|
      it "formats as #{format}" do
        result = described_class.format(obj, format)
        expect(result).to send(matcher, expected)
      end
    end

    describe ':puts format' do
      it 'uses puts semantics for arrays, one item per line, not to_s' do
        result = described_class.format([1, 2, 3], :puts)
        expect(result).to eq("1\n2\n3\n")
      end

      it 'differs from Array#to_s' do
        result = described_class.format([1, 2, 3], :puts)
        expect(result).not_to eq([1, 2, 3].to_s)
      end
    end

    describe ':pretty_print format' do
      it 'produces multi-line pretty-printed output for nested objects' do
        nested = { 'first_key'  => [1, 2, { 'nested_key' => 'nested_value' }],
                   'second_key' => %w[alpha beta gamma delta epsilon zeta] }
        result = described_class.format(nested, :pretty_print)
        expect(result.lines.count).to be > 1
        expect(result).to include("\n")
      end
    end

    describe ':inspect format' do
      it "returns the object's #inspect string" do
        result = described_class.format(obj, :inspect)
        expect(result).to eq(obj.inspect)
      end
    end

    context 'when a required gem is missing' do
      before do
        error = LoadError.new('cannot load such file -- amazing_print')
        allow(described_class).to receive(:require).with('amazing_print').and_raise(error)
      end

      it 'raises a helpful LoadError' do
        expect { described_class.format(obj, :amazing_print) }
          .to raise_error(LoadError, /requires the 'amazing_print' gem/)
      end
    end

    context 'when amazing_print is available' do
      before do
        allow(described_class).to receive(:require).with('amazing_print')
        allow(obj).to receive(:ai).and_return('amazing output')
      end

      it 'formats using amazing_print' do
        result = described_class.format(obj, :amazing_print)
        expect(result).to eq('amazing output')
      end
    end

    describe 'output_chars: :ascii mode' do
      let(:unicode_obj) { { 'name' => 'café', 'symbol' => '→' } }

      it 'produces ASCII-only JSON output' do
        result = described_class.format(unicode_obj, :json, output_chars: :ascii)
        # JSON ascii_only: true escapes non-ASCII as \uXXXX
        expect(result).not_to include('é')
        expect(result).not_to include('→')
        expect(result).to include('\\u')
      end

      it 'produces ASCII-only pretty JSON output' do
        result = described_class.format(unicode_obj, :pretty_json, output_chars: :ascii)
        expect(result).not_to include('é')
        expect(result).not_to include('→')
        expect(result).to include('\\u')
      end

      it 'produces ASCII-only YAML output' do
        result = described_class.format(unicode_obj, :yaml, output_chars: :ascii)
        # OutputChars.convert transliterates é -> e and → -> ->
        expect(result).not_to include('é')
        expect(result).not_to include('→')
        expect(result).to include('cafe') # é transliterated to e
      end

      context 'with amazing_print' do
        before do
          allow(described_class).to receive(:require).with('amazing_print')
          allow(unicode_obj).to receive(:ai).and_return('café → result')
        end

        it 'converts amazing_print output to ASCII' do
          result = described_class.format(unicode_obj, :amazing_print, output_chars: :ascii)
          expect(result).not_to include('é')
          expect(result).not_to include('→')
          expect(result).to include('cafe')
          expect(result).to include('->')
        end
      end

      # NOTE: Ruby's own #inspect/PP already escape non-ASCII characters as \uXXXX
      # when Encoding.default_external isn't UTF-8-compatible, independent of
      # OutputChars' own transliteration. Assert only that no raw multi-byte
      # characters survive, since the exact escaped form is locale-dependent.
      it 'produces ASCII-only inspect output' do
        result = described_class.format(unicode_obj, :inspect, output_chars: :ascii)
        expect(result).not_to include('é')
        expect(result).not_to include('→')
      end

      it 'produces ASCII-only puts output' do
        result = described_class.format(unicode_obj, :puts, output_chars: :ascii)
        expect(result).not_to include('é')
        expect(result).not_to include('→')
      end

      it 'produces ASCII-only pretty_print output' do
        result = described_class.format(unicode_obj, :pretty_print, output_chars: :ascii)
        expect(result).not_to include('é')
        expect(result).not_to include('→')
      end
    end
  end
end
