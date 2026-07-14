# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe CovLoupe::CoverageFileLoader do
  describe '.load' do
    it 'routes a JSON formatter document to CoverageJsonLoader' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'coverage.json')
        coverage = { 'lib/foo.rb' => { 'lines' => [1, nil, 0] } }
        File.write(path, JSON.generate(
          'meta'     => { 'command_name' => 'Minitest', 'timestamp' => '2026-07-01T00:00:00Z' },
          'coverage' => coverage
        ))

        result = described_class.load(path: path)

        expect(result.coverage_map).to eq(coverage)
        expect(result.suite_names).to eq(['Minitest'])
      end
    end

    it 'routes a resultset document to ResultsetLoader' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.resultset.json')
        coverage = { File.join(dir, 'lib', 'foo.rb') => { 'lines' => [1, 0] } }
        File.write(path, JSON.generate('RSpec' => { 'coverage' => coverage, 'timestamp' => 42 }))

        result = described_class.load(path: path)

        expect(result.coverage_map).to eq(coverage)
        expect(result.timestamp).to eq(42)
        expect(result.suite_names).to eq(['RSpec'])
      end
    end

    it 'detects by content rather than filename' do
      Dir.mktmpdir do |dir|
        # A JSON formatter document stored under the resultset's name still
        # loads through the coverage.json path.
        path = File.join(dir, '.resultset.json')
        coverage = { 'lib/foo.rb' => { 'lines' => [nil, 1] } }
        File.write(path, JSON.generate(
          'meta'     => { 'command_name' => 'RSpec', 'timestamp' => 7 },
          'coverage' => coverage
        ))

        result = described_class.load(path: path)

        expect(result.coverage_map).to eq(coverage)
        expect(result.timestamp).to eq(7)
      end
    end
  end
end
