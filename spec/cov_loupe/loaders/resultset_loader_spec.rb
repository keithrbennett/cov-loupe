# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe CovLoupe::ResultsetLoader do
  describe '.load' do
    it 'parses a single suite and returns coverage map and timestamp' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        coverage = {
          File.join(dir, 'lib', 'foo.rb') => { 'lines' => [1, 0, nil, 2] },
        }
        data = {
          'SuiteA' => {
            'timestamp' => 123,
            'coverage'  => coverage,
          },
        }
        File.write(resultset_path, JSON.generate(data))

        result = described_class.load(resultset_path: resultset_path)

        expect(result.coverage_map).to eq(coverage)
        expect(result.timestamp).to eq(123)
        expect(result.suite_names).to eq(['SuiteA'])
      end
    end

    it 'merges multiple suites and combines coverage' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        foo_path = File.join(dir, 'lib', 'foo.rb')
        bar_path = File.join(dir, 'lib', 'bar.rb')

        data = {
          'RSpec'    => {
            'timestamp' => 100,
            'coverage'  => {
              foo_path => { 'lines' => [1, 0, nil, 0] },
            },
          },
          'Cucumber' => {
            'timestamp' => 200,
            'coverage'  => {
              foo_path => { 'lines' => [0, 3, nil, 1] },
              bar_path => { 'lines' => [0, 1, 1] },
            },
          },
        }
        File.write(resultset_path, JSON.generate(data))

        result = described_class.load(resultset_path: resultset_path)
        expect(result.coverage_map[foo_path]['lines']).to eq([1, 3, nil, 1])
        expect(result.coverage_map[bar_path]['lines']).to eq([0, 1, 1])
        expect(result.timestamp).to eq(200)
        expect(result.suite_names).to contain_exactly('RSpec', 'Cucumber')
      end
    end

    it 'adapts legacy array coverage entries' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        foo_path = File.join(dir, 'lib', 'foo.rb')
        data = {
          'SuiteA' => {
            'timestamp' => 50,
            'coverage'  => {
              foo_path => [1, 0, nil, 2],
            },
          },
        }
        File.write(resultset_path, JSON.generate(data))

        result = described_class.load(resultset_path: resultset_path)
        expect(result.coverage_map[foo_path]).to eq('lines' => [1, 0, nil, 2])
      end
    end

    it 'raises CoverageDataError when no suites are present' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        File.write(resultset_path, '{}')

        expect do
          described_class.load(resultset_path: resultset_path)
        end.to raise_error(CovLoupe::CoverageDataError, /No test suite/)
      end
    end

    it 'raises CoverageDataError when coverage data is not a hash' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        data = {
          'SuiteA' => {
            'timestamp' => 10,
            'coverage'  => [],
          },
        }
        File.write(resultset_path, JSON.generate(data))

        expect do
          described_class.load(resultset_path: resultset_path)
        end.to raise_error(CovLoupe::CoverageDataError, /Invalid coverage data structure/)
      end
    end

    it 'raises Errno::ENOENT when file does not exist' do
      expect do
        described_class.load(resultset_path: '/nonexistent/path/.resultset.json')
      end.to raise_error(Errno::ENOENT)
    end

    [
      { desc: 'malformed JSON', content: '{ "invalid": json }' },
      { desc: 'empty file', content: '' },
      { desc: 'whitespace-only file', content: "   \n\t  " },
    ].each do |tc|
      it "raises JSON::ParserError for #{tc[:desc]}" do
        Dir.mktmpdir do |dir|
          resultset_path = File.join(dir, '.resultset.json')
          File.write(resultset_path, tc[:content])

          expect do
            described_class.load(resultset_path: resultset_path)
          end.to raise_error(JSON::ParserError)
        end
      end
    end
  end

  describe 'SimpleCov loading and logging' do
    let(:mock_logger) { instance_double(CovLoupe::Logger, safe_log: nil) }
    let(:loader) do
      described_class.new(resultset_path: File.join(Dir.tmpdir, 'resultset.json'), logger: mock_logger)
    end

    it 'raises CoverageDataError when SimpleCov cannot be required' do
      # We need to mock require on the instance or Kernel, but require is private.
      # The original test mocked it on described_class singleton?
      # Wait, require_simplecov_for_merge! calls `require 'simplecov'`.
      # That's Kernel.require.

      # The previous test did: singleton.send(:define_method, :require) ...
      # But now it's an instance method.

      allow(loader).to receive(:require).with('simplecov').and_raise(LoadError)

      expect do
        loader.send(:require_simplecov_for_merge!)
      end.to raise_error(CovLoupe::CoverageDataError, /Install simplecov/)
    end

    it 'logs duplicate suite names when merging coverage' do
      suites = [
        described_class::SuiteEntry.new(name: 'RSpec', coverage: {}, timestamp: 0),
        described_class::SuiteEntry.new(name: 'RSpec', coverage: {}, timestamp: 0),
        described_class::SuiteEntry.new(name: 'Cucumber', coverage: {}, timestamp: 0),
      ]

      expect(mock_logger).to receive(:safe_log)
        .with(include('Merging duplicate coverage suites for RSpec'))
      loader.send(:log_duplicate_suite_names, suites)
    end
  end

  describe 'timestamp normalization' do
    let(:mock_logger) { instance_double(CovLoupe::Logger, safe_log: nil) }
    let(:loader) { described_class.new(resultset_path: 'dummy', logger: mock_logger) }

    [
      { desc: 'float timestamps', input: 123.9, expected: 123 },
      { desc: 'Time objects', input: Time.at(456), expected: 456 },
      { desc: 'numeric string timestamps', input: '789.42', expected: 789 },
      { desc: 'created_at fallback', input: nil, created_at: 321, expected: 321 },
    ].each do |tc|
      it "handles #{tc[:desc]}" do
        value = loader.send(:normalize_coverage_timestamp, tc[:input], tc[:created_at])
        expect(value).to eq(tc[:expected])
      end
    end

    [
      {
        desc:  'invalid timestamp strings',
        input: 'not-a-timestamp',
        msgs:  ['Coverage timestamp could not be parsed', 'not-a-timestamp'],
      },
      {
        desc:  'unsupported types',
        input: [:invalid],
        msgs:  ['Coverage timestamp could not be parsed', '[:invalid]'],
      },
      {
        desc:  'blank string timestamps',
        input: '   ',
        msgs:  ['Coverage timestamp missing, defaulting to 0', '"   "'],
      },
      {
        desc:  'zero timestamps',
        input: 0,
        msgs:  ['Coverage timestamp missing, defaulting to 0', '0'],
      },
    ].each do |tc|
      it "logs warning and returns zero for #{tc[:desc]}" do
        messages = []
        allow(mock_logger).to receive(:safe_log) { |msg| messages << msg }

        value = loader.send(:normalize_coverage_timestamp, tc[:input], nil)

        expect(value).to eq(0)
        tc[:msgs].each do |msg|
          expect(messages.join).to include(msg)
        end
      end
    end
  end

  describe 'security: json_class protection' do
    it 'does not instantiate arbitrary objects from json_class attributes' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        foo_path = File.join(dir, 'lib', 'foo.rb')
        # Create a malicious payload that would execute code if JSON.load_file were used
        # With JSON.parse, json_class is just treated as a regular string key
        malicious_json = <<~JSON
          {
            "RSpec": {
              "json_class": "File",
              "args": ["/etc/passwd"],
              "timestamp": 123,
              "coverage": {
                "#{foo_path}": { "lines": [1, 0] }
              }
            }
          }
        JSON
        File.write(resultset_path, malicious_json)

        # Should parse successfully without instantiating File class
        result = described_class.load(resultset_path: resultset_path)
        expect(result.coverage_map).to be_a(Hash)
        expect(result.coverage_map[foo_path]).to eq('lines' => [1, 0])
        expect(result.suite_names).to eq(['RSpec'])
      end
    end

    it 'treats json_class as ordinary string keys in coverage data' do
      Dir.mktmpdir do |dir|
        resultset_path = File.join(dir, '.resultset.json')
        foo_path = File.join(dir, 'lib', 'foo.rb')
        # Coverage data that includes json_class as a harmless string key
        data = {
          'SuiteA' => {
            'timestamp' => 100,
            'coverage'  => {
              foo_path => { 'lines' => [1, 0], 'json_class' => 'IgnoredString' },
            },
          },
        }
        File.write(resultset_path, JSON.generate(data))

        result = described_class.load(resultset_path: resultset_path)
        expect(result.coverage_map[foo_path]['lines']).to eq([1, 0])
        expect(result.coverage_map[foo_path]['json_class']).to eq('IgnoredString')
      end
    end
  end
end
