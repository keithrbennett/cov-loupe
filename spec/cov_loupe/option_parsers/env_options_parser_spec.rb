# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/option_parsers/env_options_parser'

RSpec.describe CovLoupe::OptionParsers::EnvOptionsParser do
  let(:parser) { described_class.new }

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
          ENV['COV_LOUPE_OPTS'] = tc[:env]
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

  describe 'custom environment variable name' do
    around do |example|
      originals = ENV.to_h.slice('CUSTOM_OPTS', 'MY_CUSTOM_VAR')
      example.run
    ensure
      %w[CUSTOM_OPTS MY_CUSTOM_VAR].each { |name| ENV[name] = originals[name] }
    end

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
