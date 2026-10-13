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

    it 'raises when a specified directory does not contain coverage.json' do
      nested_dir = File.join(root, 'coverage')
      Dir.mkdir(nested_dir)

      expect do
        resolver.find_coverage_file(coverage_file: nested_dir)
      end.to raise_error(CovLoupe::CoverageFileNotFoundError,
        /No coverage.json found in directory/)
    end

    it 'returns the resolved path when a valid coverage file is provided' do
      file = File.join(root, 'custom.json')
      File.write(file, '{}')

      expect(resolver.find_coverage_file(coverage_file: file)).to eq(file)
    end

    it 'locates coverage.json inside a provided directory' do
      Dir.mktmpdir do |dir|
        nested = File.join(dir, 'coverage')
        FileUtils.mkdir_p(nested)
        File.write(File.join(nested, 'coverage.json'), '{}')

        resolver = described_class.new(root: dir)
        expect(resolver.find_coverage_file(coverage_file: nested))
          .to eq(File.join(nested, 'coverage.json'))
      end
    end

    it 'raises a helpful error when the default coverage file is absent' do
      expect do
        resolver.find_coverage_file
      end.to raise_error(CovLoupe::CoverageFileNotFoundError,
        /Could not find coverage.json/)
    end

    it 'accepts a coverage file path already nested under the provided root without double-prefixing' do
      project_root = (FIXTURES_DIR / 'project1').to_s
      resolver = described_class.new(root: project_root)

      resolved = resolver.find_coverage_file(coverage_file: 'spec/fixtures/project1/coverage')

      expect(resolved).to eq(File.join(project_root, 'coverage', 'coverage.json'))
    end

    it 'raises when a relative coverage file path is ambiguous between root and Dir.pwd' do
      FileUtils.mkdir_p(File.join(root, 'coverage'))
      File.write(File.join(root, 'coverage', 'coverage.json'), '{}')

      Dir.mktmpdir do |pwd|
        FileUtils.mkdir_p(File.join(pwd, 'coverage'))
        File.write(File.join(pwd, 'coverage', 'coverage.json'), '{}')

        Dir.chdir(pwd) do
          expect do
            resolver.find_coverage_file(coverage_file: 'coverage')
          end.to raise_error(CovLoupe::ConfigurationError, /Ambiguous coverage file location specified/)
        end
      end
    end

    it 'prefers the root candidate when the Dir.pwd candidate is missing' do
      FileUtils.mkdir_p(File.join(root, 'coverage'))
      File.write(File.join(root, 'coverage', 'coverage.json'), '{}')

      Dir.mktmpdir do |pwd|
        Dir.chdir(pwd) do
          resolved = resolver.find_coverage_file(coverage_file: 'coverage')
          expect(resolved).to eq(File.join(root, 'coverage', 'coverage.json'))
        end
      end
    end
  end

  describe 'default coverage file' do
    it 'finds only coverage/coverage.json under the root' do
      Dir.mktmpdir do |root|
        resolver = described_class.new(root: root)
        FileUtils.mkdir_p(File.join(root, 'coverage'))
        FileUtils.mkdir_p(File.join(root, 'tmp'))
        coverage_dir_file = File.join(root, 'coverage', 'coverage.json')

        aggregate_failures do
          # Locations that earlier versions searched are no longer discovered.
          File.write(File.join(root, 'coverage.json'), '{}')
          File.write(File.join(root, 'tmp', 'coverage.json'), '{}')
          expect { resolver.find_coverage_file }
            .to raise_error(CovLoupe::CoverageFileNotFoundError, /Could not find coverage.json/)

          File.write(coverage_dir_file, '{}')
          expect(resolver.find_coverage_file).to eq(coverage_dir_file)
        end
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
