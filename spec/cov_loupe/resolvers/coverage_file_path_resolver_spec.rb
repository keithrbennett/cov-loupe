# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe CovLoupe::Resolvers::CoverageFilePathResolver do
  describe '#find_coverage_file' do
    let(:root) { Dir.mktmpdir }
    let(:resolver) { described_class.new(root: root) }

    after do
      FileUtils.remove_entry(root) if root && Dir.exist?(root)
    end

    it 'raises when a specified coverage file cannot be found' do
      expect do
        resolver.find_coverage_file(coverage_file: 'missing.json')
      end.to raise_error(CovLoupe::CoverageFileNotFoundError, /Specified coverage file not found/)
    end

    it 'raises when a specified directory does not contain .resultset.json' do
      nested_dir = File.join(root, 'coverage')
      Dir.mkdir(nested_dir)

      expect do
        resolver.find_coverage_file(coverage_file: nested_dir)
      end.to raise_error(CovLoupe::CoverageFileNotFoundError,
        /No coverage.json or .resultset.json found in directory/)
    end

    it 'returns the resolved path when a valid coverage file is provided' do
      file = File.join(root, 'custom.json')
      File.write(file, '{}')

      expect(resolver.find_coverage_file(coverage_file: file)).to eq(file)
    end

    it 'locates .resultset.json inside a provided directory' do
      Dir.mktmpdir do |dir|
        nested = File.join(dir, 'coverage')
        FileUtils.mkdir_p(nested)
        File.write(File.join(nested, '.resultset.json'), '{}')

        resolver = described_class.new(root: dir)
        expect(resolver.find_coverage_file(coverage_file: nested))
          .to eq(File.join(nested, '.resultset.json'))
      end
    end

    it 'raises a helpful error when no fallback candidates are found' do
      expect do
        resolver.find_resultset
      end.to raise_error(CovLoupe::CoverageFileNotFoundError,
        /Could not find coverage.json or .resultset.json/)
    end

    it 'accepts a coverage file path already nested under the provided root without double-prefixing' do
      project_root = (FIXTURES_DIR / 'project1').to_s
      resolver = described_class.new(root: project_root)

      resolved = resolver.find_coverage_file(coverage_file: 'spec/fixtures/project1/coverage')

      expect(resolved).to eq(File.join(project_root, 'coverage', '.resultset.json'))
    end

    it 'raises when a relative coverage file path is ambiguous between root and Dir.pwd' do
      FileUtils.mkdir_p(File.join(root, 'coverage'))
      File.write(File.join(root, 'coverage', '.resultset.json'), '{}')

      Dir.mktmpdir do |pwd|
        FileUtils.mkdir_p(File.join(pwd, 'coverage'))
        File.write(File.join(pwd, 'coverage', '.resultset.json'), '{}')

        Dir.chdir(pwd) do
          expect do
            resolver.find_coverage_file(coverage_file: 'coverage')
          end.to raise_error(CovLoupe::ConfigurationError, /Ambiguous coverage file location specified/)
        end
      end
    end

    it 'prefers the root candidate when the Dir.pwd candidate is missing' do
      FileUtils.mkdir_p(File.join(root, 'coverage'))
      File.write(File.join(root, 'coverage', '.resultset.json'), '{}')

      Dir.mktmpdir do |pwd|
        Dir.chdir(pwd) do
          resolved = resolver.find_coverage_file(coverage_file: 'coverage')
          expect(resolved).to eq(File.join(root, 'coverage', '.resultset.json'))
        end
      end
    end

    # In non-strict mode, resolve_candidate returns nil instead of raising
    # when the path doesn't exist, allowing fallback resolution to continue.
    it 'returns nil for non-existent path in non-strict mode' do
      result = resolver.send(:resolve_candidate, '/nonexistent/path.json', strict: false)
      expect(result).to be_nil
    end
  end

  describe 'coverage.json support' do
    it 'prefers coverage.json over .resultset.json in the default candidates' do
      Dir.mktmpdir do |root|
        coverage_dir = File.join(root, 'coverage')
        FileUtils.mkdir_p(coverage_dir)
        File.write(File.join(coverage_dir, 'coverage.json'), '{}')
        File.write(File.join(coverage_dir, '.resultset.json'), '{}')

        resolver = described_class.new(root: root)

        expect(resolver.find_resultset).to eq(File.join(coverage_dir, 'coverage.json'))
      end
    end

    it 'prefers coverage.json when resolving an explicit directory containing both' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'coverage.json'), '{}')
        File.write(File.join(dir, '.resultset.json'), '{}')

        resolver = described_class.new(root: dir)

        expect(resolver.find_coverage_file(coverage_file: dir)).to eq(File.join(dir, 'coverage.json'))
      end
    end

    it 'falls back to .resultset.json when no coverage.json exists' do
      Dir.mktmpdir do |root|
        coverage_dir = File.join(root, 'coverage')
        FileUtils.mkdir_p(coverage_dir)
        File.write(File.join(coverage_dir, '.resultset.json'), '{}')

        resolver = described_class.new(root: root)

        expect(resolver.find_resultset).to eq(File.join(coverage_dir, '.resultset.json'))
      end
    end
  end

  describe 'private #within_root?' do
    it 'delegates to PathUtils.within_root? for root checks' do
      Dir.mktmpdir do |root|
        resolver = described_class.new(root: root)
        inside = File.join(root, 'lib')

        outside_root = Dir.mktmpdir
        outside = File.join(outside_root, 'lib')

        expect(resolver.send(:within_root?, inside)).to be(true)
        expect(resolver.send(:within_root?, outside)).to be(false)
      ensure
        FileUtils.remove_entry(outside_root) if outside_root && Dir.exist?(outside_root)
      end
    end
  end
end
