# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe CovLoupe::CoverageJsonLoader do
  # A representative SimpleCov 1.0.0 JSON formatter document: top-level
  # $schema, meta, total, project-relative file keys.
  def coverage_json_document(coverage:, timestamp: '2026-07-01T12:00:00.000+00:00', command_name: 'RSpec')
    {
      '$schema'  => 'https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/coverage-v1.0.schema.json',
      'meta'     => {
        'schema_version'    => '1.0',
        'simplecov_version' => '1.0.0',
        'command_name'      => command_name,
        'timestamp'         => timestamp,
      },
      'total'    => { 'lines' => { 'covered' => 2, 'missed' => 1, 'total' => 3, 'percent' => 66.67 } },
      'coverage' => coverage,
      'groups'   => {},
      'errors'   => {},
    }
  end

  describe '.coverage_json?' do
    it 'is true for a JSON formatter document' do
      doc = coverage_json_document(coverage: { 'lib/foo.rb' => { 'lines' => [1, 0, nil] } })
      expect(described_class.coverage_json?(doc)).to be(true)
    end

    it 'is false for a resultset document' do
      doc = { 'RSpec' => { 'coverage' => { 'lib/foo.rb' => { 'lines' => [1] } }, 'timestamp' => 1 } }
      expect(described_class.coverage_json?(doc)).to be(false)
    end

    it 'is false for non-hash input' do
      expect(described_class.coverage_json?([1, 2])).to be(false)
    end
  end

  describe '.load' do
    it 'returns the coverage map, epoch timestamp, and command name' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        coverage = { 'lib/foo.rb' => { 'lines' => [1, 0, nil, 2], 'branches' => [] } }
        File.write(path, JSON.generate(coverage_json_document(coverage: coverage)))

        result = described_class.load(path: path)

        expect(result.coverage_map).to eq(coverage)
        expect(result.timestamp).to eq(Time.parse('2026-07-01T12:00:00.000+00:00').to_i)
        expect(result.suite_names).to eq(['RSpec'])
      end
    end

    it 'defaults the timestamp to 0 when meta has none' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        doc = coverage_json_document(coverage: { 'lib/foo.rb' => { 'lines' => [1] } })
        doc['meta'].delete('timestamp')
        File.write(path, JSON.generate(doc))

        result = described_class.load(path: path)

        expect(result.timestamp).to eq(0)
      end
    end

    it 'loads pre-1.0 JSON formatter documents (absolute keys, sparse meta, "ignored" markers)' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        # The exact shape simplecov_json_formatter produced for SimpleCov
        # 0.18 through 0.22: meta carries only the version, file keys are
        # absolute, and :nocov: lines are marked with the string "ignored".
        legacy = {
          'meta'     => { 'simplecov_version' => '0.22.0' },
          'coverage' => {
            '/abs/path/lib/demo.rb' => { 'lines' => [1, 1, nil, 'ignored', 'ignored', 1, 0] },
          },
          'groups'   => {},
        }
        File.write(path, JSON.generate(legacy))

        result = described_class.load(path: path)

        expect(result.coverage_map).to eq(
          '/abs/path/lib/demo.rb' => { 'lines' => [1, 1, nil, nil, nil, 1, 0] }
        )
        expect(result.timestamp).to eq(0)
        expect(result.suite_names).to eq([])
      end
    end

    it 'maps "ignored" markers to nil in 1.0 documents too' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        doc = coverage_json_document(coverage: { 'lib/foo.rb' => { 'lines' => ['ignored', 1, 0] } })
        File.write(path, JSON.generate(doc))

        result = described_class.load(path: path)

        expect(result.coverage_map['lib/foo.rb']['lines']).to eq([nil, 1, 0])
      end
    end

    it 'leaves unrecognized strings in place for the line array validation to reject' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        doc = coverage_json_document(coverage: { 'lib/foo.rb' => { 'lines' => [1, 'bad', 'ignored', 0] } })
        File.write(path, JSON.generate(doc))

        result = described_class.load(path: path)

        # Only the "ignored" sentinel becomes nil; "bad" survives so it is
        # caught downstream instead of passing as a non-executable line.
        expect(result.coverage_map['lib/foo.rb']['lines']).to eq([1, 'bad', nil, 0])

        resolver = CovLoupe::Resolvers::CoverageLineResolver.new(
          result.coverage_map, root: dir, volume_case_sensitive: true
        )
        expect { resolver.lookup_lines('lib/foo.rb') }
          .to raise_error(CovLoupe::CoverageDataError, /non-integer elements: \["bad"\]/)
      end
    end

    it 'raises CoverageDataError for a document without the expected structure' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        File.write(path, JSON.generate('RSpec' => { 'coverage' => {} }))

        expect { described_class.load(path: path) }
          .to raise_error(CovLoupe::CoverageDataError, /Not a SimpleCov JSON formatter document/)
      end
    end
  end
end
