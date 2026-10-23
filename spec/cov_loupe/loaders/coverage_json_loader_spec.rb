# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe CovLoupe::CoverageJsonLoader do
  let(:logger) { instance_double(CovLoupe::Logger, safe_log: nil) }

  def write_and_load(dir, document)
    path = File.join(dir, 'coverage.json')
    File.write(path, JSON.generate(document))
    described_class.load(resolved_coverage_file: path, logger: logger)
  end

  describe '.load' do
    it 'returns the coverage map and the meta timestamp as epoch seconds' do
      Dir.mktmpdir do |dir|
        coverage = { 'lib/foo.rb' => { 'lines' => [1, 0, nil, 2], 'branches' => [] } }
        timestamp = '2026-07-01T12:00:00.000+00:00'

        result = write_and_load(dir, coverage_json_document(coverage: coverage, timestamp: timestamp))

        expect(result.coverage_map).to eq(coverage)
        expect(result.timestamp).to eq(Time.parse(timestamp).to_i)
      end
    end

    [
      { desc: 'a US-ASCII default external', external: Encoding::US_ASCII, internal: nil },
      { desc: 'a US-ASCII default internal', external: Encoding::UTF_8, internal: Encoding::US_ASCII },
    ].each do |tc|
      it "reads non-ASCII paths as UTF-8 with #{tc[:desc]} encoding" do
        Dir.mktmpdir do |dir|
          coverage = { "lib/caf\u00e9\u2192.rb" => { 'lines' => [1] } }
          path = File.join(dir, 'coverage.json')
          File.write(path, JSON.generate(coverage_json_document(coverage: coverage)))

          result = with_default_encodings(external: tc[:external], internal: tc[:internal]) do
            described_class.load(resolved_coverage_file: path, logger: logger)
          end

          expect(result.coverage_map.keys).to eq(coverage.keys)
        end
      end
    end

    it 'accepts an epoch number as the timestamp' do
      Dir.mktmpdir do |dir|
        document = coverage_json_document(coverage: {})
        document['meta']['timestamp'] = 1_720_000_000.5

        expect(write_and_load(dir, document).timestamp).to eq(1_720_000_000)
      end
    end

    [
      { desc: 'meta has no timestamp', timestamp: nil, log: /timestamp missing/ },
      { desc: 'the timestamp is unparseable', timestamp: 'not a time', log: /could not be parsed/ },
      { desc: 'the timestamp is neither a string nor a number', timestamp: [1], log: /could not be parsed/ },
    ].each do |tc|
      it "defaults the timestamp to 0 and logs when #{tc[:desc]}" do
        Dir.mktmpdir do |dir|
          document = coverage_json_document(coverage: {}, timestamp: tc[:timestamp])

          expect(write_and_load(dir, document).timestamp).to eq(0)
          expect(logger).to have_received(:safe_log).with(tc[:log])
        end
      end
    end

    it 'maps "ignored" markers to nil' do
      Dir.mktmpdir do |dir|
        coverage = { 'lib/foo.rb' => { 'lines' => ['ignored', 1, nil, 'ignored', 0] } }

        result = write_and_load(dir, coverage_json_document(coverage: coverage))

        expect(result.coverage_map['lib/foo.rb']['lines']).to eq([nil, 1, nil, nil, 0])
      end
    end

    it 'leaves unrecognized strings in place for the line array validation to reject' do
      Dir.mktmpdir do |dir|
        coverage = { 'lib/foo.rb' => { 'lines' => [1, 'bad', 'ignored', 0] } }

        result = write_and_load(dir, coverage_json_document(coverage: coverage))

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

    [
      { desc: 'a resultset document', document: { 'RSpec' => { 'coverage' => {}, 'timestamp' => 1 } } },
      { desc: 'a document whose coverage is not a map', document: { 'meta' => {}, 'coverage' => [] } },
      { desc: 'a document without meta', document: { 'coverage' => {} } },
      { desc: 'a non-object document', document: [1, 2] },
    ].each do |tc|
      it "raises CoverageDataError for #{tc[:desc]}" do
        Dir.mktmpdir do |dir|
          expect { write_and_load(dir, tc[:document]) }
            .to raise_error(CovLoupe::CoverageDataError, /Not a SimpleCov coverage.json document/)
        end
      end
    end

    %w[1.0 1.3].each do |version|
      it "loads a document whose meta.schema_version is #{version}" do
        Dir.mktmpdir do |dir|
          document = coverage_json_document(coverage: {})
          document['meta']['schema_version'] = version

          expect(write_and_load(dir, document).coverage_map).to eq({})
        end
      end
    end

    [
      { desc: 'missing', mutate: ->(meta) { meta.delete('schema_version') }, shown: 'nil' },
      { desc: 'nil', mutate: ->(meta) { meta['schema_version'] = nil }, shown: 'nil' },
      { desc: '"0.9"', mutate: ->(meta) { meta['schema_version'] = '0.9' }, shown: '"0.9"' },
      { desc: '"2.0"', mutate: ->(meta) { meta['schema_version'] = '2.0' }, shown: '"2.0"' },
      { desc: '"10.0"', mutate: ->(meta) { meta['schema_version'] = '10.0' }, shown: '"10.0"' },
      { desc: 'a number', mutate: ->(meta) { meta['schema_version'] = 1 }, shown: '1' },
    ].each do |tc|
      it "raises CoverageDataError naming the value when meta.schema_version is #{tc[:desc]}" do
        Dir.mktmpdir do |dir|
          document = coverage_json_document(coverage: {})
          tc[:mutate].call(document['meta'])
          path = File.join(dir, 'coverage.json')

          expect { write_and_load(dir, document) }.to raise_error(CovLoupe::CoverageDataError) { |error|
            expect(error.message).to include("meta.schema_version: #{tc[:shown]}")
            expect(error.message).to include('meta.simplecov_version: "1.0.0"', path, 'requires format 1.x')
          }
        end
      end
    end

    it 'omits the SimpleCov version from the format error when meta has none' do
      Dir.mktmpdir do |dir|
        document = coverage_json_document(coverage: {})
        document['meta'].delete('simplecov_version')
        document['meta']['schema_version'] = '2.0'

        expect { write_and_load(dir, document) }
          .to raise_error(CovLoupe::CoverageDataError) { |error| expect(error.message).not_to include('simplecov_version') }
      end
    end

    it 'raises Errno::ENOENT when the file does not exist' do
      expect do
        described_class.load(resolved_coverage_file: '/nonexistent/path/coverage.json', logger: logger)
      end
        .to raise_error(Errno::ENOENT)
    end

    # A truncated write or a wrong -c path can hand the loader non-JSON content.
    [
      { desc: 'malformed JSON', content: '{ "invalid": json }' },
      { desc: 'an empty file', content: '' },
      { desc: 'a whitespace-only file', content: "   \n\t  " },
    ].each do |tc|
      it "raises JSON::ParserError for #{tc[:desc]}" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'coverage.json')
          File.write(path, tc[:content])

          expect { described_class.load(resolved_coverage_file: path, logger: logger) }
            .to raise_error(JSON::ParserError)
        end
      end
    end
  end
end
