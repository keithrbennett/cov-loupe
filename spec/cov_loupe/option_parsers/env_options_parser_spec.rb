# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::OptionParsers::EnvOptionsParser do
  let(:parser) { described_class.new }

  around do |example|
    original_value = ENV['COV_LOUPE_OPTS']
    example.run
  ensure
    ENV['COV_LOUPE_OPTS'] = original_value
  end

  describe '#parse_env_opts' do
    context 'with valid inputs' do
      [
        {
          desc:     'environment variable is not set',
          env:      nil,
          expected: [],
        },
        {
          desc:     'environment variable is empty string',
          env:      '',
          expected: [],
        },
        {
          desc:     'environment variable contains only whitespace',
          env:      '   ',
          expected: [],
        },
        {
          desc:     'simple options',
          env:      '--error-mode off --format json',
          expected: %w[--error-mode off --format json],
        },
        {
          desc:     'quoted strings with spaces',
          env:      '--coverage-file "/path/to/my file.json"',
          expected: ['--coverage-file', '/path/to/my file.json'],
        },
        {
          desc:     'complex shell escaping scenarios',
          env:      '--coverage-file "/path/with spaces/file.json" --error-mode on',
          expected: ['--coverage-file', '/path/with spaces/file.json', '--error-mode', 'on'],
        },
        {
          desc:     'single quotes',
          env:      "--coverage-file '/path/with spaces/file.json'",
          expected: ['--coverage-file', '/path/with spaces/file.json'],
        },
        {
          desc:     'escaped characters',
          env:      '--coverage-file /path/with\\ spaces/file.json',
          expected: ['--coverage-file', '/path/with spaces/file.json'],
        },
        {
          desc:     'mixed quoting styles',
          env:      '--option1 "value with spaces" --option2 \'another value\'',
          expected: ['--option1', 'value with spaces', '--option2', 'another value'],
        },
      ].each do |tc|
        it "handles #{tc[:desc]}" do
          if tc[:env].nil?
            ENV.delete('COV_LOUPE_OPTS')
          else
            ENV['COV_LOUPE_OPTS'] = tc[:env]
          end
          expect(parser.parse_env_opts).to eq(tc[:expected])
        end
      end
    end

    context 'with malformed inputs' do
      [
        { desc: 'unmatched double quotes', env: '--coverage-file "unterminated string' },
        { desc: 'unmatched single quotes', env: "--coverage-file 'unterminated string" },
        { desc: 'multiple quoting errors', env: '"first "second "third' },
      ].each do |tc|
        it "raises ConfigurationError for #{tc[:desc]}" do
          ENV['COV_LOUPE_OPTS'] = tc[:env]
          expect do
            parser.parse_env_opts
          end.to raise_error(CovLoupe::ConfigurationError, /Invalid COV_LOUPE_OPTS format/)
        end
      end

      it 'raises ConfigurationError with descriptive message' do
        ENV['COV_LOUPE_OPTS'] = '--option "bad quote'

        expect do
          parser.parse_env_opts
        end.to raise_error(CovLoupe::ConfigurationError) do |error|
          expect(error.message).to include('Invalid COV_LOUPE_OPTS format')
          expect(error.message).to include('Unmatched') # from Shellwords error
        end
      end
    end
  end

  describe '#pre_scan_error_mode' do
    let(:error_mode_normalizer) { parser.send(:method, :normalize_error_mode) }

    context 'when error-mode is found' do
      it 'extracts error-mode with space separator' do
        argv = %w[--error-mode debug --other-option]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:debug)
      end

      it 'extracts error-mode with equals separator' do
        argv = %w[--error-mode=off --other-option]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:off)
      end

      it 'handles error-mode with equals but empty value' do
        argv = %w[--error-mode= --other-option]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        # Empty value resolves to default :log
        expect(result).to eq(:log)
      end

      it 'returns last error-mode when multiple are present' do
        argv = %w[--error-mode log --error-mode off]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:off)
      end

      it 'supports short -e flag' do
        argv = %w[-e debug]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:debug)
      end

      it 'supports attached short -e flag (-edebug)' do
        argv = %w[-edebug]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:debug)
      end

      it 'returns default for -e=debug because optparse does not strip equals for short options' do
        argv = %w[-e=debug]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:log)
      end

      it 'prioritizes later flags over earlier ones (mixed short/long)' do
        argv = %w[--error-mode log -e debug]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:debug)
      end

      it 'treats trailing empty assignment as an override (returning default)' do
        # Simulates ENV providing 'off', but CLI providing invalid/empty override.
        # Should stop at the last one and return default (:log), not fall back to :off.
        argv = %w[--error-mode off --error-mode=]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to eq(:log)
      end

      it 'returns nil when a standalone option lacks a value at the end of argv' do
        %w[--error-mode -e].each do |opt|
          argv = ['--other-opt', opt]
          result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
          expect(result).to be_nil
        end
      end
    end

    context 'when error-mode is not found' do
      it 'returns nil when no error-mode is present' do
        argv = %w[--other-option value]
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to be_nil
      end

      it 'returns nil for empty argv' do
        argv = []
        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: error_mode_normalizer)
        expect(result).to be_nil
      end
    end

    context 'when handling errors during pre-scan' do
      it 'returns nil when normalizer raises an error' do
        faulty_normalizer = ->(_) { raise StandardError, 'Intentional error' }
        argv = %w[--error-mode log]

        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: faulty_normalizer)
        expect(result).to be_nil
      end

      it 'returns nil when normalizer raises ArgumentError' do
        faulty_normalizer = ->(_) { raise ArgumentError, 'Bad argument' }
        argv = %w[--error-mode log]

        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: faulty_normalizer)
        expect(result).to be_nil
      end

      it 'returns nil when normalizer raises RuntimeError' do
        faulty_normalizer = ->(_) { raise 'Runtime problem' }
        argv = %w[--error-mode=off]

        result = parser.pre_scan_error_mode(argv, error_mode_normalizer: faulty_normalizer)
        expect(result).to be_nil
      end
    end
  end

  describe '#normalize_error_mode (private)' do
    [
      { input: 'off', expected: :off },
      { input: 'OFF', expected: :off },
      { input: 'Off', expected: :off },
      { input: 'log', expected: :log },
      { input: 'LOG', expected: :log },
      { input: 'Log', expected: :log },
      { input: 'debug', expected: :debug },
      { input: 'DEBUG', expected: :debug },
      { input: 'unknown', expected: :log },
      { input: 'invalid', expected: :log },
      { input: '', expected: :log },
      { input: nil, expected: :log },
    ].each do |tc|
      it "normalizes #{tc[:input].inspect} to #{tc[:expected].inspect}" do
        expect(parser.send(:normalize_error_mode, tc[:input])).to eq(tc[:expected])
      end
    end
  end

  describe 'custom environment variable name' do
    it 'uses custom environment variable when specified' do
      custom_parser = described_class.new(env_var: 'CUSTOM_OPTS')
      ENV['CUSTOM_OPTS'] = '--error-mode off'

      expect(custom_parser.parse_env_opts).to eq(%w[--error-mode off])
    end

    it 'includes custom env var name in error messages' do
      custom_parser = described_class.new(env_var: 'MY_CUSTOM_VAR')
      ENV['MY_CUSTOM_VAR'] = '"bad quote'

      expect do
        custom_parser.parse_env_opts
      end.to raise_error(CovLoupe::ConfigurationError, /Invalid MY_CUSTOM_VAR format/)
    end
  end
end
